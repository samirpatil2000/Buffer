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
        XCTAssertEqual(HistoryLimit.allCases.count, 3)
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

    func testZoomableImageViewConstantsAndPresets() {
        XCTAssertEqual(ZoomableImageView.minScale, 1.0)
        XCTAssertEqual(ZoomableImageView.maxScale, 4.0)
        XCTAssertEqual(ZoomableImageView.defaultDoubleTapScale, 2.5)
        XCTAssertGreaterThanOrEqual(ZoomableImageView.defaultDoubleTapScale, ZoomableImageView.minScale)
        XCTAssertLessThanOrEqual(ZoomableImageView.defaultDoubleTapScale, ZoomableImageView.maxScale)
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
}

