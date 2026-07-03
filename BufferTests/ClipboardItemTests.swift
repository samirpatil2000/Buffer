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
}
