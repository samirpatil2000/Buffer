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
}
