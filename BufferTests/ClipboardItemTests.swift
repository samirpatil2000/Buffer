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
    
    func testRichTextItemEquatableAndCodable() throws {
        let id = UUID()
        let timestamp = Date()
        let rtfSample = "{\\rtf1\\ansi\\b Hello\\b0}".data(using: .utf8)
        let htmlSample = "<b>Hello</b>".data(using: .utf8)
        
        let itemPlain = ClipboardItem.text("Hello")
        let itemRich = ClipboardItem(
            id: id,
            type: .text,
            timestamp: timestamp,
            textContent: "Hello",
            rtfData: rtfSample,
            htmlData: htmlSample
        )
        let itemRichSame = ClipboardItem(
            id: id,
            type: .text,
            timestamp: timestamp,
            textContent: "Hello",
            rtfData: rtfSample,
            htmlData: htmlSample
        )
        
        XCTAssertEqual(itemRich, itemRichSame)
        XCTAssertNotEqual(itemPlain, itemRich)
        
        // Encode and decode
        let encoder = JSONEncoder()
        let data = try encoder.encode(itemRich)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ClipboardItem.self, from: data)
        
        XCTAssertEqual(decoded.id, itemRich.id)
        XCTAssertEqual(decoded.textContent, "Hello")
        XCTAssertEqual(decoded.rtfData, rtfSample)
        XCTAssertEqual(decoded.htmlData, htmlSample)
    }
}
