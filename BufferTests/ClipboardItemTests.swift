import XCTest
@testable import Buffer

class ClipboardItemTests: XCTestCase {
    func testClipboardItemEquatable() {
        let id = UUID()
        let timestamp = Date()
        
        let item1 = ClipboardItem(
            id: id,
            type: .image,
            timestamp: timestamp,
            isPinned: false,
            isBookmarked: false,
            tags: [],
            ocrText: nil
        )
        
        // Item with updated OCR text
        let itemWithOCR = ClipboardItem(
            id: id,
            type: .image,
            timestamp: timestamp,
            isPinned: false,
            isBookmarked: false,
            tags: [],
            ocrText: "extracted text"
        )
        
        // Item with updated pin state
        let itemPinned = ClipboardItem(
            id: id,
            type: .image,
            timestamp: timestamp,
            isPinned: true,
            isBookmarked: false,
            tags: [],
            ocrText: nil
        )
        
        // Item with updated bookmark state
        let itemBookmarked = ClipboardItem(
            id: id,
            type: .image,
            timestamp: timestamp,
            isPinned: false,
            isBookmarked: true,
            tags: [],
            ocrText: nil
        )
        
        // Item with updated tags
        let itemWithTags = ClipboardItem(
            id: id,
            type: .image,
            timestamp: timestamp,
            isPinned: false,
            isBookmarked: false,
            tags: ["tag1"],
            ocrText: nil
        )
        
        XCTAssertNotEqual(item1, itemWithOCR, "Items with different OCR text should not be equal")
        XCTAssertNotEqual(item1, itemPinned, "Items with different pin state should not be equal")
        XCTAssertNotEqual(item1, itemBookmarked, "Items with different bookmark state should not be equal")
        XCTAssertNotEqual(item1, itemWithTags, "Items with different tags should not be equal")
        XCTAssertEqual(item1, item1, "Identical items should be equal")
    }

    func testMinimumTextLengthFilter() {
        XCTAssertFalse(ClipboardWatcher.shouldCaptureText("", minimumLength: 1))
        XCTAssertFalse(ClipboardWatcher.shouldCaptureText("ab", minimumLength: 3))
        XCTAssertTrue(ClipboardWatcher.shouldCaptureText("abc", minimumLength: 3))
        XCTAssertTrue(ClipboardWatcher.shouldCaptureText("👨‍👩‍👧‍👦", minimumLength: 1))
    }

    func testDuplicateInlineTextLookup() {
        let first = ClipboardItem.text("first")
        let duplicate = ClipboardItem.text("duplicate")
        let items = [first, duplicate]

        XCTAssertEqual(
            ClipboardStore.duplicateInlineTextIndex(for: .text("duplicate"), in: items),
            1
        )
        XCTAssertNil(
            ClipboardStore.duplicateInlineTextIndex(for: .text("new"), in: items)
        )
        XCTAssertNil(
            ClipboardStore.duplicateInlineTextIndex(
                for: .largeText(preview: "duplicate", filename: "large.txt"),
                in: items
            )
        )
    }

    func testUpdateInfoAndVersionComparison() {
        XCTAssertTrue(UpdateService.versionIsNewer("2.1.0", than: "2.0.0"))
        XCTAssertTrue(UpdateService.versionIsNewer("2.0.1", than: "2.0.0"))
        XCTAssertFalse(UpdateService.versionIsNewer("2.0.0", than: "2.0.0"))
        XCTAssertFalse(UpdateService.versionIsNewer("1.9.9", than: "2.0.0"))
        XCTAssertTrue(UpdateService.versionIsNewer("10.0.0", than: "9.9.9"))

        XCTAssertEqual(UpdateService.stripTagPrefix("v2.1.0"), "2.1.0")
        XCTAssertEqual(UpdateService.stripTagPrefix("buffer-v2.1.0"), "2.1.0")
        XCTAssertEqual(UpdateService.stripTagPrefix("2.1.0"), "2.1.0")

        let info1 = UpdateInfo(version: "2.1.0", tag: "v2.1.0", downloadURL: "https://example.com/update.zip", releaseNotes: "Bug fixes")
        let info2 = UpdateInfo(version: "2.1.0", tag: "v2.1.0", downloadURL: "https://example.com/update.zip", releaseNotes: "Bug fixes")
        let info3 = UpdateInfo(version: "2.2.0", tag: "v2.2.0", downloadURL: "https://example.com/update2.zip", releaseNotes: nil)

        XCTAssertEqual(info1, info2)
        XCTAssertNotEqual(info1, info3)
        XCTAssertEqual(
            info1.targetReleaseURL.absoluteString,
            "https://github.com/samirpatil2000/Buffer/releases/tag/v2.1.0"
        )
        let infoCustom = UpdateInfo(
            version: "2.7.0",
            tag: "buffer-v2.7.0",
            downloadURL: "https://example.com/buffer-v2.7.0.zip",
            releaseNotes: "Cool stuff",
            releaseURL: URL(string: "https://github.com/samirpatil2000/Buffer/releases/tag/buffer-v2.7.0")
        )
        XCTAssertEqual(
            infoCustom.targetReleaseURL.absoluteString,
            "https://github.com/samirpatil2000/Buffer/releases/tag/buffer-v2.7.0"
        )
    }

    func testUpdateServicePublishedState() {
        let service = UpdateService.shared
        let originalUpdate = service.availableUpdate

        let testInfo = UpdateInfo(version: "99.0.0", tag: "v99.0.0", downloadURL: "https://example.com/test.zip", releaseNotes: "Test release")
        service.availableUpdate = testInfo
        XCTAssertEqual(service.availableUpdate, testInfo)

        service.availableUpdate = nil
        XCTAssertNil(service.availableUpdate)

        service.availableUpdate = originalUpdate
    }

    func testUpdateCheckIntervalAndPeriodicChecking() {
        let service = UpdateService.shared
        XCTAssertEqual(service.updateCheckInterval, 3600)
        service.startPeriodicChecking()
        service.updateCheckInterval = 120
        XCTAssertEqual(service.updateCheckInterval, 120)
        service.stopPeriodicChecking()
        service.updateCheckInterval = 3600
    }

    func testShouldCheckForUpdatesThrottling() {
        let now = Date()
        let interval: TimeInterval = 3600 // 1 hour

        // 1. Never checked before
        XCTAssertTrue(UpdateService.shouldCheckForUpdates(lastCheckDate: nil, interval: interval, currentDate: now))

        // 2. Checked 30 minutes ago (< 1 hour)
        let thirtyMinutesAgo = now.addingTimeInterval(-1800)
        XCTAssertFalse(UpdateService.shouldCheckForUpdates(lastCheckDate: thirtyMinutesAgo, interval: interval, currentDate: now))

        // 3. Checked 59 minutes ago (< 1 hour)
        let fiftyNineMinutesAgo = now.addingTimeInterval(-3540)
        XCTAssertFalse(UpdateService.shouldCheckForUpdates(lastCheckDate: fiftyNineMinutesAgo, interval: interval, currentDate: now))

        // 4. Checked exactly 60 minutes ago (>= 1 hour)
        let sixtyMinutesAgo = now.addingTimeInterval(-3600)
        XCTAssertTrue(UpdateService.shouldCheckForUpdates(lastCheckDate: sixtyMinutesAgo, interval: interval, currentDate: now))

        // 5. Checked 2 hours ago (>= 1 hour)
        let twoHoursAgo = now.addingTimeInterval(-7200)
        XCTAssertTrue(UpdateService.shouldCheckForUpdates(lastCheckDate: twoHoursAgo, interval: interval, currentDate: now))
    }

    func testHistoryWindowAutosaveAndSizeConstants() {
        XCTAssertEqual(HistoryWindowController.windowAutosaveName, "BufferHistoryWindow")
        XCTAssertEqual(HistoryWindowController.defaultWindowSize.width, 700)
        XCTAssertEqual(HistoryWindowController.defaultWindowSize.height, 480)
        XCTAssertEqual(HistoryWindowController.minWindowSize.width, 600)
        XCTAssertEqual(HistoryWindowController.minWindowSize.height, 400)
    }

    func testBufferOpenSettingsWindowNotification() {
        let exp = expectation(description: "bufferOpenSettingsWindow received")
        let observer = NotificationCenter.default.addObserver(
            forName: .bufferOpenSettingsWindow,
            object: nil,
            queue: .main
        ) { _ in
            exp.fulfill()
        }
        
        NotificationCenter.default.post(name: .bufferOpenSettingsWindow, object: nil)
        wait(for: [exp], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }

    func testContentZoomScaleInSettingsManager() {
        let settings = SettingsManager.shared
        let original = settings.contentZoomScale
        defer {
            settings.contentZoomScale = original
            settings.save()
        }

        settings.zoomReset()
        XCTAssertEqual(settings.contentZoomScale, 1.0)

        // Step up
        settings.zoomIn()
        XCTAssertEqual(settings.contentZoomScale, 1.15)
        settings.zoomIn()
        XCTAssertEqual(settings.contentZoomScale, 1.3)
        settings.zoomIn()
        XCTAssertEqual(settings.contentZoomScale, 1.5)
        // Clamp max
        settings.zoomIn()
        XCTAssertEqual(settings.contentZoomScale, 1.5)

        // Step down
        settings.zoomOut()
        XCTAssertEqual(settings.contentZoomScale, 1.3)
        settings.zoomOut()
        XCTAssertEqual(settings.contentZoomScale, 1.15)
        settings.zoomOut()
        XCTAssertEqual(settings.contentZoomScale, 1.0)
        settings.zoomOut()
        XCTAssertEqual(settings.contentZoomScale, 0.9)
        settings.zoomOut()
        XCTAssertEqual(settings.contentZoomScale, 0.8)
        // Clamp min
        settings.zoomOut()
        XCTAssertEqual(settings.contentZoomScale, 0.8)

        // Reset
        settings.zoomReset()
        XCTAssertEqual(settings.contentZoomScale, 1.0)
    }

    func testHistoryLimitTiersAndReduction() {
        XCTAssertEqual(HistoryLimit.allCases.count, 4)
        XCTAssertEqual(HistoryLimit.essential.maxCount, 200)
        XCTAssertEqual(HistoryLimit.deep.maxCount, 1000)
        XCTAssertNil(HistoryLimit.unlimited.maxCount)

        XCTAssertEqual(HistoryLimit.essential.subtitle, "200 items")
        XCTAssertEqual(HistoryLimit.deep.subtitle, "1,000 items")
        XCTAssertEqual(HistoryLimit.unlimited.subtitle, "No limit")

        // Reductions
        XCTAssertTrue(HistoryLimit.essential.isReduction(from: .deep))
        XCTAssertTrue(HistoryLimit.essential.isReduction(from: .unlimited))
        XCTAssertTrue(HistoryLimit.deep.isReduction(from: .unlimited))

        // Increases or same
        XCTAssertFalse(HistoryLimit.deep.isReduction(from: .essential))
        XCTAssertFalse(HistoryLimit.unlimited.isReduction(from: .essential))
        XCTAssertFalse(HistoryLimit.unlimited.isReduction(from: .deep))
        XCTAssertFalse(HistoryLimit.essential.isReduction(from: .essential))
        XCTAssertFalse(HistoryLimit.unlimited.isReduction(from: .unlimited))
    }

    func testCustomHistoryLimitTier() {
        let originalCustomLimit = HistoryLimit.customHistoryLimit
        defer { HistoryLimit.customHistoryLimit = originalCustomLimit }

        HistoryLimit.customHistoryLimit = 5000

        XCTAssertEqual(HistoryLimit.custom.maxCount, 5000)
        XCTAssertEqual(HistoryLimit.custom.label, "Custom")
        // Grouping separator is locale-dependent (e.g. "5,000" vs "5.000"), so compare
        // against the live formatted value rather than hardcoding a separator.
        XCTAssertEqual(HistoryLimit.custom.subtitle, "\(5000.formatted()) items")
    }

    func testHistoryLimitIsReductionAllPairwiseCombinations() {
        let originalCustomLimit = HistoryLimit.customHistoryLimit
        defer { HistoryLimit.customHistoryLimit = originalCustomLimit }
        HistoryLimit.customHistoryLimit = 20_000

        // essential (200) vs itself and others
        XCTAssertFalse(HistoryLimit.essential.isReduction(from: .essential), "essential->essential: equal caps, not a reduction")
        XCTAssertTrue(HistoryLimit.essential.isReduction(from: .deep), "essential->deep: 200 < 1000, reduction")
        XCTAssertTrue(HistoryLimit.essential.isReduction(from: .unlimited), "essential->unlimited: finite from nil, reduction")
        XCTAssertTrue(HistoryLimit.essential.isReduction(from: .custom), "essential->custom: 200 < 20000, reduction")

        // deep (1000) vs others
        XCTAssertFalse(HistoryLimit.deep.isReduction(from: .essential), "deep->essential: 1000 is not < 200, not a reduction")
        XCTAssertFalse(HistoryLimit.deep.isReduction(from: .deep), "deep->deep: equal caps, not a reduction")
        XCTAssertTrue(HistoryLimit.deep.isReduction(from: .unlimited), "deep->unlimited: finite from nil, reduction")
        XCTAssertTrue(HistoryLimit.deep.isReduction(from: .custom), "deep->custom: 1000 < 20000, reduction")

        // unlimited (nil) vs others
        XCTAssertFalse(HistoryLimit.unlimited.isReduction(from: .essential), "unlimited->essential: target has no max, not a reduction")
        XCTAssertFalse(HistoryLimit.unlimited.isReduction(from: .deep), "unlimited->deep: target has no max, not a reduction")
        XCTAssertFalse(HistoryLimit.unlimited.isReduction(from: .unlimited), "unlimited->unlimited: target has no max, not a reduction")
        XCTAssertFalse(HistoryLimit.unlimited.isReduction(from: .custom), "unlimited->custom: second guard returns false because target has no max")

        // custom (20000) vs others
        XCTAssertFalse(HistoryLimit.custom.isReduction(from: .essential), "custom->essential: 20000 is not < 200, not a reduction")
        XCTAssertFalse(HistoryLimit.custom.isReduction(from: .deep), "custom->deep: 20000 is not < 1000, not a reduction")
        XCTAssertTrue(HistoryLimit.custom.isReduction(from: .unlimited), "custom->unlimited: first guard returns self != .unlimited, which is true")
        XCTAssertFalse(HistoryLimit.custom.isReduction(from: .custom), "custom->custom: targetMax < currentMax is false for equal caps")
    }

    func testSearchMatchesTextAndOCRButNotEmptySentinel() {
        let textItem = ClipboardItem.text("hello world")
        XCTAssertTrue(ClipboardItem.matches(item: textItem, query: "world"), "text item should match by textContent")

        let imageWithOCR = ClipboardItem(type: .image, imageFilename: "img1.png", ocrText: "scanned receipt total")
        XCTAssertTrue(ClipboardItem.matches(item: imageWithOCR, query: "receipt"), "image item should match by non-empty ocrText")

        let imageWithEmptySentinel = ClipboardItem(type: .image, imageFilename: "img2.png", ocrText: "")
        XCTAssertFalse(ClipboardItem.matches(item: imageWithEmptySentinel, query: "receipt"), "empty ocrText sentinel must never match a non-empty query")

        let imageWithNilOCR = ClipboardItem(type: .image, imageFilename: "img3.png", ocrText: nil)
        XCTAssertFalse(ClipboardItem.matches(item: imageWithNilOCR, query: "receipt"), "nil ocrText must never match")

        // Feature 3 (combined items): matches() is type-agnostic by construction - a combined
        // item (type == .text, non-empty imageFilenames) matches by textContent exactly like
        // any other text item, with no special-casing required.
        var combinedItem = ClipboardItem.text("combined item body text")
        combinedItem.imageFilenames = ["attachment.png"]
        XCTAssertTrue(ClipboardItem.matches(item: combinedItem, query: "body"), "combined item should match by textContent like any text item")
    }

    // MARK: - Rich-text preservation (feature 3, commit 3a)

    func testLegacyDecodeWithoutRichTextKeys() throws {
        // Build the exact JSON shape by encoding sample items first, then stripping the new
        // keys this feature adds - this guarantees the date/UUID format matches exactly what
        // JSONEncoder produces, without hand-guessing the format.
        let textID = UUID()
        let textTimestamp = Date()
        let sampleText = ClipboardItem(
            id: textID, type: .text, timestamp: textTimestamp, sourceApp: "TestApp",
            textContent: "legacy text", isPinned: true, isBookmarked: false,
            tags: ["tag1"], ocrText: nil, isTruncated: false, originalSizeBytes: nil
        )
        let imageID = UUID()
        let imageTimestamp = Date()
        let sampleImage = ClipboardItem(
            id: imageID, type: .image, timestamp: imageTimestamp, sourceApp: nil,
            imageFilename: "legacy.png", isPinned: false, isBookmarked: true,
            tags: [], ocrText: "scanned text", isTruncated: false, originalSizeBytes: nil
        )

        let encoded = try JSONEncoder().encode([sampleText, sampleImage])
        var jsonArray = try JSONSerialization.jsonObject(with: encoded) as! [[String: Any]]
        // Strip the new keys this feature adds, to simulate a genuinely pre-feature payload.
        for i in jsonArray.indices {
            jsonArray[i].removeValue(forKey: "rtfData")
            jsonArray[i].removeValue(forKey: "htmlData")
            jsonArray[i].removeValue(forKey: "rtfdData")
            jsonArray[i].removeValue(forKey: "imageFilenames")
        }
        let legacyData = try JSONSerialization.data(withJSONObject: jsonArray)

        let decoded = try JSONDecoder().decode([ClipboardItem].self, from: legacyData)
        XCTAssertEqual(decoded.count, 2)

        let decodedText = decoded[0]
        XCTAssertEqual(decodedText.id, textID)
        XCTAssertEqual(decodedText.type, .text)
        XCTAssertEqual(decodedText.textContent, "legacy text")
        XCTAssertEqual(decodedText.sourceApp, "TestApp")
        XCTAssertTrue(decodedText.isPinned)
        XCTAssertEqual(decodedText.tags, ["tag1"])
        XCTAssertNil(decodedText.ocrText)
        XCTAssertNil(decodedText.rtfData, "legacy item without rtfData key must decode to nil")
        XCTAssertNil(decodedText.htmlData, "legacy item without htmlData key must decode to nil")
        XCTAssertNil(decodedText.rtfdData, "legacy item without rtfdData key must decode to nil")
        XCTAssertEqual(decodedText.imageFilenames, [], "legacy item without imageFilenames key must decode to []")

        let decodedImage = decoded[1]
        XCTAssertEqual(decodedImage.id, imageID)
        XCTAssertEqual(decodedImage.type, .image)
        XCTAssertEqual(decodedImage.imageFilename, "legacy.png")
        XCTAssertTrue(decodedImage.isBookmarked)
        XCTAssertEqual(decodedImage.ocrText, "scanned text")
        XCTAssertNil(decodedImage.rtfData)
        XCTAssertNil(decodedImage.htmlData)
        XCTAssertNil(decodedImage.rtfdData)
        XCTAssertEqual(decodedImage.imageFilenames, [])
    }

    func testRichTextDataRoundTrip() throws {
        let rtf = "sample rtf".data(using: .utf8)!
        let html = "<p>sample html</p>".data(using: .utf8)!
        let rtfd = "sample rtfd".data(using: .utf8)!
        var item = ClipboardItem.text("styled text", sourceApp: "Notes", rtfData: rtf, htmlData: html, rtfdData: rtfd)
        item.imageFilenames = ["attachment1.png", "attachment2.png"]

        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: encoded)

        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded.rtfData, rtf)
        XCTAssertEqual(decoded.htmlData, html)
        XCTAssertEqual(decoded.rtfdData, rtfd)
        XCTAssertEqual(decoded.imageFilenames, ["attachment1.png", "attachment2.png"])
    }

    func testLegacyItemsEncodeWithoutNewKeys() throws {
        let item = ClipboardItem.text("x")
        let encoded = try JSONEncoder().encode(item)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        XCTAssertNil(json["rtfData"], "an item with no rich data must not add rtfData to the JSON")
        XCTAssertNil(json["htmlData"], "an item with no rich data must not add htmlData to the JSON")
        XCTAssertNil(json["rtfdData"], "an item with no rich data must not add rtfdData to the JSON")
        XCTAssertNil(json["imageFilenames"], "an item with no attachments must not add imageFilenames to the JSON")
    }

    func testHasRichTextCombinations() {
        let neither = ClipboardItem.text("a")
        XCTAssertFalse(neither.hasRichText)

        let rtfOnly = ClipboardItem.text("a", rtfData: Data([0x01]))
        XCTAssertTrue(rtfOnly.hasRichText)

        let htmlOnly = ClipboardItem.text("a", htmlData: Data([0x01]))
        XCTAssertTrue(htmlOnly.hasRichText)

        let both = ClipboardItem.text("a", rtfData: Data([0x01]), htmlData: Data([0x01]))
        XCTAssertTrue(both.hasRichText)
    }

    // MARK: - Combined items (feature 3, commit 3b)

    func testPreviewTextForAllShapes() {
        var combinedWithBody = ClipboardItem.text("some body text")
        combinedWithBody.imageFilenames = ["a.png"]
        XCTAssertEqual(combinedWithBody.previewText, "some body text")

        var combinedEmptyBody = ClipboardItem.text("")
        combinedEmptyBody.imageFilenames = ["a.png"]
        XCTAssertEqual(combinedEmptyBody.previewText, "Image", "combined item with an empty body should render as Image, not blank")

        let pureImage = ClipboardItem.image(filename: "pure.png")
        XCTAssertEqual(pureImage.previewText, "Image")

        let pureText = ClipboardItem.text("plain text")
        XCTAssertEqual(pureText.previewText, "plain text")

        let emptyPureText = ClipboardItem.text("")
        XCTAssertEqual(emptyPureText.previewText, "", "empty pure text item should render as an empty string, exactly as today")
    }

    func testTypeLabelAndImageAggregationForAllShapes() {
        let pureText = ClipboardItem.text("x")
        XCTAssertEqual(pureText.typeLabel, "Text")
        XCTAssertFalse(pureText.hasImages)
        XCTAssertFalse(pureText.isCombined)
        XCTAssertFalse(pureText.hasAttachedImages)

        let pureImage = ClipboardItem.image(filename: "pure.png")
        XCTAssertEqual(pureImage.typeLabel, "Image")
        XCTAssertEqual(pureImage.allImageFilenames, ["pure.png"])
        XCTAssertTrue(pureImage.hasImages)
        XCTAssertFalse(pureImage.isCombined, "a pure image item is never isCombined - that predicate requires type == .text")
        XCTAssertFalse(pureImage.hasAttachedImages, "pure image uses imageFilename, not imageFilenames")

        var combinedOne = ClipboardItem.text("x")
        combinedOne.imageFilenames = ["attachment.png"]
        XCTAssertEqual(combinedOne.typeLabel, "Text + Image")
        XCTAssertEqual(combinedOne.allImageFilenames, ["attachment.png"])
        XCTAssertTrue(combinedOne.hasImages)
        XCTAssertTrue(combinedOne.isCombined)
        XCTAssertTrue(combinedOne.hasAttachedImages)

        var combinedMany = ClipboardItem.text("x")
        combinedMany.imageFilenames = ["a1.png", "a2.png", "a3.png"]
        XCTAssertEqual(combinedMany.typeLabel, "Text + 3 Images")
        XCTAssertTrue(combinedMany.isCombined)

        // allImageFilenames ordering: pure imageFilename first, then attachments in order.
        // This combination (both imageFilename and imageFilenames set) is never produced by the
        // capture path, but the computed property must still order correctly if it ever occurs.
        var withBoth = ClipboardItem(type: .text, textContent: "x", imageFilename: "first.png")
        withBoth.imageFilenames = ["second.png", "third.png"]
        XCTAssertEqual(withBoth.allImageFilenames, ["first.png", "second.png", "third.png"])
    }

    func testDuplicateInlineTextIndexExcludesCombinedItems() {
        let pureText = ClipboardItem.text("same body")
        var combined = ClipboardItem.text("same body")
        combined.imageFilenames = ["attachment.png"]
        let items = [pureText, combined]

        // A combined item is never considered a duplicate of a pure-text item with the same body.
        XCTAssertNil(
            ClipboardStore.duplicateInlineTextIndex(for: combined, in: items),
            "a combined item must never match as a duplicate, even with identical text"
        )

        // Existing pure-text duplicate detection still works unchanged.
        XCTAssertEqual(
            ClipboardStore.duplicateInlineTextIndex(for: .text("same body"), in: items),
            0,
            "a pure-text item should still match an existing pure-text duplicate"
        )
    }

    func testZoomableImageViewConstantsAndPresets() {
        XCTAssertEqual(ZoomableImageView.minScale, 1.0)
        XCTAssertEqual(ZoomableImageView.maxScale, 4.0)
        XCTAssertEqual(ZoomableImageView.defaultDoubleTapScale, 2.5)
        XCTAssertGreaterThanOrEqual(ZoomableImageView.defaultDoubleTapScale, ZoomableImageView.minScale)
        XCTAssertLessThanOrEqual(ZoomableImageView.defaultDoubleTapScale, ZoomableImageView.maxScale)
    }

    // MARK: - Feature 4: LanguageDetector heuristics

    func testDetectorLeavesProsePlain() {
        let prose = "This is an ordinary paragraph of English text that a person might copy from an article or an email, with nothing code-like about it at all."
        XCTAssertEqual(LanguageDetector.detect(prose), .plain)
    }

    func testDetectorIgnoresShortFragments() {
        XCTAssertEqual(LanguageDetector.detect("hello"), .plain)
        XCTAssertEqual(LanguageDetector.detect("a short line"), .plain)
    }

    func testDetectorRecognizesJSON() {
        let json = "{\"name\": \"buffer\", \"version\": 2, \"tags\": [\"a\", \"b\"]}"
        XCTAssertEqual(LanguageDetector.detect(json), .code(hint: "json"))
    }

    func testDetectorRejectsInvalidJSONAsPlainOrCode() {
        // Looks brace-y but is not valid JSON; must not be reported as json.
        let notJSON = "{ this is not json at all, just prose in braces maybe }"
        if case .code(let hint) = LanguageDetector.detect(notJSON) {
            XCTAssertNotEqual(hint, "json")
        }
    }

    func testDetectorRecognizesShellShebang() {
        XCTAssertEqual(LanguageDetector.detect("#!/bin/bash\necho hello world here"), .code(hint: "bash"))
        XCTAssertEqual(LanguageDetector.detect("#!/usr/bin/env python\nprint('hi there')"), .code(hint: "python"))
    }

    func testDetectorRecognizesDiff() {
        let diff = "diff --git a/file.txt b/file.txt\n--- a/file.txt\n+++ b/file.txt\n@@ -1 +1 @@\n-old\n+new"
        XCTAssertEqual(LanguageDetector.detect(diff), .code(hint: "diff"))
    }

    func testDetectorRecognizesSQL() {
        let sql = "SELECT id, name FROM users WHERE active = 1 ORDER BY name;"
        XCTAssertEqual(LanguageDetector.detect(sql), .code(hint: nil))
    }

    func testDetectorRecognizesXMLHTML() {
        let html = "<!DOCTYPE html>\n<html><body><div>hi</div></body></html>"
        XCTAssertEqual(LanguageDetector.detect(html), .code(hint: "xml"))
    }

    func testDetectorRecognizesGenericCode() {
        let swift = "func greet(name: String) -> String {\n    return \"Hello, \\(name)\"\n}"
        if case .plain = LanguageDetector.detect(swift) {
            XCTFail("Expected code detection for a Swift function body")
        }
    }

    // MARK: - Feature 4: language override Codable round-trip

    func testLanguageFieldRoundTrips() throws {
        let item = ClipboardItem(type: .text, textContent: "SELECT 1", language: "sql")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)
        XCTAssertEqual(decoded.language, "sql")
    }

    func testForcedPlainEmptyLanguageRoundTrips() throws {
        let item = ClipboardItem(type: .text, textContent: "not code", language: "")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)
        XCTAssertEqual(decoded.language, "")
    }

    func testOldPayloadWithoutLanguageDecodes() throws {
        // A history.json entry written before feature 4 existed: no "language" key.
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "type": "text",
            "timestamp": 760000000,
            "textContent": "hello",
            "isPinned": false,
            "isBookmarked": false,
            "tags": [],
            "isTruncated": false
        }
        """
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: Data(json.utf8))
        XCTAssertNil(decoded.language)
        XCTAssertEqual(decoded.textContent, "hello")
    }

    // MARK: - Format button: CodeFormatter

    func testFormatterPrettyPrintsMinifiedJSON() {
        let minified = "{\"b\":2,\"a\":[1,2,3]}"
        let result = CodeFormatter.format(minified, language: "json")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("\n"), "formatted JSON should be multi-line")
        // Key order is preserved (not sorted): b before a.
        let bIndex = result!.range(of: "\"b\"")!.lowerBound
        let aIndex = result!.range(of: "\"a\"")!.lowerBound
        XCTAssertLessThan(bIndex, aIndex)
    }

    func testFormatterRejectsInvalidJSON() {
        XCTAssertNil(CodeFormatter.format("{not valid json", language: "json"))
    }

    func testFormatterCanFormatDetectsJSONAndXML() {
        XCTAssertTrue(CodeFormatter.canFormat(language: nil, text: "{\"a\":1}"))
        XCTAssertTrue(CodeFormatter.canFormat(language: "xml", text: "<a><b/></a>"))
        XCTAssertFalse(CodeFormatter.canFormat(language: "swift", text: "let x = 1"))
        XCTAssertFalse(CodeFormatter.canFormat(language: nil, text: "just some prose here"))
    }

    // MARK: - Remote image URL extraction (opt-in download feature)

    func testRemoteImageURLExtraction() {
        let html = """
        <div>
          <img src="https://example.com/a.png" alt="a">
          <img src='http://example.com/b.jpg'>
          <img src="/relative/c.png">
          <img src="data:image/png;base64,AAAA">
          <img src="https://example.com/a.png">
        </div>
        """
        let urls = ClipboardWatcher.remoteImageURLs(fromHTML: html)
        let strings = urls.map { $0.absoluteString }
        // Absolute http(s) only, de-duplicated, relative and data: skipped.
        XCTAssertEqual(strings, ["https://example.com/a.png", "http://example.com/b.jpg"])
    }

    func testRemoteImageURLExtractionEmptyWhenNoImages() {
        XCTAssertTrue(ClipboardWatcher.remoteImageURLs(fromHTML: "<p>no images here</p>").isEmpty)
    }

    func testRemoteImageURLExtractionIgnoresDataURIs() {
        // data: images are handled by the inline-data path, not the remote-download path.
        let html = "<img src=\"data:image/png;base64,iVBORw0KGgo=\">"
        XCTAssertTrue(ClipboardWatcher.remoteImageURLs(fromHTML: html).isEmpty)
    }

    // MARK: - Hyperlink extraction

    func testLinkExtractionFromHTML() {
        let html = """
        <p>See <a href="https://example.com/a">Ticket A</a> and
        <a href='http://example.com/b'>Ticket B</a> or email
        <a href="mailto:x@example.com">us</a>.</p>
        <a href="#frag">skip</a>
        <a href="/relative">skip</a>
        <a href="javascript:void(0)">skip</a>
        """
        let links = ClipboardWatcher.extractLinks(fromHTML: html)
        XCTAssertEqual(links, [
            WebLink(text: "Ticket A", url: "https://example.com/a"),
            WebLink(text: "Ticket B", url: "http://example.com/b"),
            WebLink(text: "us", url: "mailto:x@example.com"),
        ])
    }

    func testLinkExtractionStripsInnerTagsAndDeDupes() {
        let html = """
        <a href="https://example.com"><b>Bold</b> label</a>
        <a href="https://example.com"><b>Bold</b> label</a>
        """
        let links = ClipboardWatcher.extractLinks(fromHTML: html)
        XCTAssertEqual(links, [WebLink(text: "Bold label", url: "https://example.com")])
    }

    func testLinkExtractionEmptyWhenNoAnchors() {
        XCTAssertTrue(ClipboardWatcher.extractLinks(fromHTML: "<p>no links here</p>").isEmpty)
    }

    func testLinksMatchSearch() {
        let item = ClipboardItem(type: .text, textContent: "see ticket",
                                 links: [WebLink(text: "FIQS-1909", url: "https://jira/browse/FIQS-1909")])
        XCTAssertTrue(ClipboardItem.matches(item: item, query: "FIQS-1909"))  // anchor text
        XCTAssertTrue(ClipboardItem.matches(item: item, query: "jira"))       // url
        XCTAssertFalse(ClipboardItem.matches(item: item, query: "nope"))
    }

    func testLinksRoundTripCodable() throws {
        let item = ClipboardItem(type: .text, textContent: "x",
                                 links: [WebLink(text: "A", url: "https://a.com")])
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)
        XCTAssertEqual(decoded.links, [WebLink(text: "A", url: "https://a.com")])
    }

    func testOldPayloadWithoutLinksDecodesToEmpty() throws {
        let json = """
        { "id": "\(UUID().uuidString)", "type": "text", "timestamp": 760000000,
          "textContent": "hi", "isPinned": false, "isBookmarked": false,
          "tags": [], "isTruncated": false }
        """
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.links.isEmpty)
    }

    func testDetectBareURLsInPlainText() {
        let text = "see https://example.com/a and http://example.com/b plus mailto:x@y.com, not ftp://z"
        let urls = ClipboardWatcher.detectURLs(in: text)
        XCTAssertTrue(urls.contains("https://example.com/a"))
        XCTAssertTrue(urls.contains("http://example.com/b"))
        XCTAssertFalse(urls.contains(where: { $0.hasPrefix("ftp") }))
    }

    func testDetectBareURLsEmptyWhenNone() {
        XCTAssertTrue(ClipboardWatcher.detectURLs(in: "just some words, no links").isEmpty)
    }

    func testSelectionRangeIndexCalculations() {
        // Forward expansion
        XCTAssertEqual(SelectionRangeHelper.indexRange(anchor: 2, target: 5), 2...5)
        // Upward / reverse expansion
        XCTAssertEqual(SelectionRangeHelper.indexRange(anchor: 5, target: 2), 2...5)
        // Single item at anchor
        XCTAssertEqual(SelectionRangeHelper.indexRange(anchor: 3, target: 3), 3...3)
    }

    func testSelectionRangeExpansionAndContraction() {
        let items = [
            ClipboardItem.text("item 0"),
            ClipboardItem.text("item 1"),
            ClipboardItem.text("item 2"),
            ClipboardItem.text("item 3"),
            ClipboardItem.text("item 4")
        ]

        let anchor = 2
        // Initial state: anchor selected
        let initialIDs = SelectionRangeHelper.rangeSelectedIDs(anchorIndex: anchor, targetIndex: 2, items: items)
        XCTAssertEqual(initialIDs, [items[2].id])

        // Shift + Down -> 2...3 (2 items)
        let step1 = SelectionRangeHelper.rangeSelectedIDs(anchorIndex: anchor, targetIndex: 3, items: items)
        XCTAssertEqual(step1, [items[2].id, items[3].id])

        // Shift + Down -> 2...4 (3 items)
        let step2 = SelectionRangeHelper.rangeSelectedIDs(anchorIndex: anchor, targetIndex: 4, items: items)
        XCTAssertEqual(step2, [items[2].id, items[3].id, items[4].id])

        // Shift + Up (Contracting!) -> 2...3 (item 4 is removed)
        let step3 = SelectionRangeHelper.rangeSelectedIDs(anchorIndex: anchor, targetIndex: 3, items: items)
        XCTAssertEqual(step3, [items[2].id, items[3].id])
        XCTAssertFalse(step3.contains(items[4].id), "Step 3 must not contain item 4 after shrinking upward")

        // Shift + Up (Contracting to anchor) -> 2...2 (item 3 is removed)
        let step4 = SelectionRangeHelper.rangeSelectedIDs(anchorIndex: anchor, targetIndex: 2, items: items)
        XCTAssertEqual(step4, [items[2].id])
        XCTAssertFalse(step4.contains(items[3].id), "Step 4 must not contain item 3 after shrinking to anchor")

        // Shift + Up (Crossing anchor upward!) -> 1...2 (item 1 and item 2)
        let step5 = SelectionRangeHelper.rangeSelectedIDs(anchorIndex: anchor, targetIndex: 1, items: items)
        XCTAssertEqual(step5, [items[1].id, items[2].id])

        // Shift + Down (Contracting back to anchor from above!) -> 2...2
        let step6 = SelectionRangeHelper.rangeSelectedIDs(anchorIndex: anchor, targetIndex: 2, items: items)
        XCTAssertEqual(step6, [items[2].id])
        XCTAssertFalse(step6.contains(items[1].id), "Step 6 must not contain item 1 after shrinking back to anchor")
    }

    func testSelectionRangeResolveAnchorFallback() {
        let items = [
            ClipboardItem.text("first"),
            ClipboardItem.text("second"),
            ClipboardItem.text("third")
        ]

        // Valid anchor
        let resolved = SelectionRangeHelper.resolveAnchorIndex(anchorID: items[1].id, fallbackIndex: 0, items: items)
        XCTAssertEqual(resolved?.index, 1)
        XCTAssertEqual(resolved?.id, items[1].id)

        // Missing anchor falls back to fallbackIndex
        let missingID = UUID()
        let fallback = SelectionRangeHelper.resolveAnchorIndex(anchorID: missingID, fallbackIndex: 2, items: items)
        XCTAssertEqual(fallback?.index, 2)
        XCTAssertEqual(fallback?.id, items[2].id)

        // Nil anchor falls back to clamped fallbackIndex
        let nilAnchor = SelectionRangeHelper.resolveAnchorIndex(anchorID: nil, fallbackIndex: 10, items: items)
        XCTAssertEqual(nilAnchor?.index, 2)
        XCTAssertEqual(nilAnchor?.id, items[2].id)

        // Empty list returns nil
        let empty: [ClipboardItem] = []
        let emptyResult = SelectionRangeHelper.resolveAnchorIndex(anchorID: items[0].id, fallbackIndex: 0, items: empty)
        XCTAssertNil(emptyResult)
    }

    func testAppThemeCasesAndProperties() {
        XCTAssertEqual(AppTheme.allCases, [.system, .light, .dark])

        XCTAssertEqual(AppTheme.system.label, "System")
        XCTAssertNil(AppTheme.system.colorScheme)
        XCTAssertNil(AppTheme.system.nsAppearance)

        XCTAssertEqual(AppTheme.light.label, "Light")
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
        XCTAssertEqual(AppTheme.light.nsAppearance?.name, NSAppearance.Name.aqua)

        XCTAssertEqual(AppTheme.dark.label, "Dark")
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
        XCTAssertEqual(AppTheme.dark.nsAppearance?.name, NSAppearance.Name.darkAqua)
    }

    func testAppThemeSettingsPersistenceAndNotification() {
        let initialTheme = SettingsManager.shared.appTheme
        let expectation = expectation(forNotification: .bufferThemeChanged, object: nil)

        let viewModel = SettingsViewModel()
        let targetTheme: AppTheme = (initialTheme == .dark) ? .light : .dark
        viewModel.appTheme = targetTheme
        viewModel.save()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(SettingsManager.shared.appTheme, targetTheme)

        let savedRaw = UserDefaults.standard.string(forKey: "appTheme")
        XCTAssertEqual(savedRaw, targetTheme.rawValue)

        // Restore initial theme
        viewModel.appTheme = initialTheme
        viewModel.save()
    }
    
    // MARK: - SyntaxDetector Tests
    
    func testSyntaxDetectorShebangShell() {
        let text = "#!/bin/bash\necho 'hello world'"
        let result = SyntaxDetector.detect(text: text)
        XCTAssertEqual(result.fileExtension, "sh")
        XCTAssertEqual(result.contentType, .shellScript)
    }
    
    func testSyntaxDetectorJSON() {
        let text = "{\n  \"name\": \"Buffer\",\n  \"version\": 1\n}"
        let result = SyntaxDetector.detect(text: text)
        XCTAssertEqual(result.fileExtension, "json")
        XCTAssertEqual(result.contentType, .json)
    }
    
    func testSyntaxDetectorGitAndBuildLog() {
        let text = """
        7d52315..b24cfa1 main -> origin/main
        Updating 7d52315..b24cfa1
        Fast-forward
        colab_runner.ipynb | 48 +++++++++++++++++
        4 files changed, 87 insertions(+), 8 deletions(-)
        === Setting up Qwen-Image-2.1 Standalone Runner ===
        cmake version 3.28
        """
        let result = SyntaxDetector.detect(text: text)
        XCTAssertEqual(result.fileExtension, "log")
    }
    
    func testSyntaxDetectorMarkdown() {
        let text = "# Release Notes\n\n- Fix issue with paste\n- Add save feature"
        let result = SyntaxDetector.detect(text: text)
        XCTAssertEqual(result.fileExtension, "md")
        XCTAssertEqual(result.suggestedFileName, "Release Notes.md")
    }
    
    func testSyntaxDetectorPython() {
        let text = "def calculate_total(items):\n    return sum(item.price for item in items)"
        let result = SyntaxDetector.detect(text: text)
        XCTAssertEqual(result.fileExtension, "py")
        XCTAssertEqual(result.contentType, .pythonScript)
    }
    
    func testSyntaxDetectorSwift() {
        let text = "import SwiftUI\n\nstruct CustomBadge: View {\n    var body: some View { Text(\"Hi\") }\n}"
        let result = SyntaxDetector.detect(text: text)
        XCTAssertEqual(result.fileExtension, "swift")
        XCTAssertEqual(result.contentType, .swiftSource)
    }
    
    func testSyntaxDetectorPlainTextFallback() {
        let text = "Hello this is a regular clipboard snippet with some random words."
        let result = SyntaxDetector.detect(text: text)
        XCTAssertEqual(result.fileExtension, "txt")
        XCTAssertEqual(result.contentType, .plainText)
    }
}


