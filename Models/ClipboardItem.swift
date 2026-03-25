import Foundation
import AppKit

/// Represents a single item in the clipboard history
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ClipboardItemType
    let timestamp: Date
    let sourceApp: String?
    
    // For text items — inline content (nil for file-backed large text)
    let textContent: String?
    
    // For large text items — filename reference (stored separately, like images)
    let textFilename: String?
    
    // For image items — filename reference (stored separately)
    let imageFilename: String?
    
    // Bookmark state
    var isBookmarked: Bool
    
    // Extracted OCR text (persisted after first extraction)
    var ocrText: String?
    
    // For extreme text items — true if content exceeded storage limit and only preview is saved
    let isTruncated: Bool
    
    // For large/extreme text items — original size in bytes (for display purposes)
    let originalSizeBytes: Int?
    
    init(id: UUID = UUID(), type: ClipboardItemType, timestamp: Date = Date(), sourceApp: String? = nil, textContent: String? = nil, textFilename: String? = nil, imageFilename: String? = nil, isBookmarked: Bool = false, ocrText: String? = nil, isTruncated: Bool = false, originalSizeBytes: Int? = nil) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.sourceApp = sourceApp
        self.textContent = textContent
        self.textFilename = textFilename
        self.imageFilename = imageFilename
        self.isBookmarked = isBookmarked
        self.ocrText = ocrText
        self.isTruncated = isTruncated
        self.originalSizeBytes = originalSizeBytes
    }
    
    /// Create a text clipboard item
    static func text(_ content: String, sourceApp: String? = nil) -> ClipboardItem {
        ClipboardItem(
            type: .text,
            sourceApp: sourceApp,
            textContent: content
        )
    }
    
    /// Create an image clipboard item
    static func image(filename: String, sourceApp: String? = nil) -> ClipboardItem {
        ClipboardItem(
            type: .image,
            sourceApp: sourceApp,
            imageFilename: filename
        )
    }
    
    /// Create a large text clipboard item (file-backed with inline preview)
    static func largeText(preview: String, filename: String, sourceApp: String? = nil) -> ClipboardItem {
        ClipboardItem(
            type: .text,
            sourceApp: sourceApp,
            textContent: preview,
            textFilename: filename
        )
    }
    
    /// Create an extremely large text item where only the preview is saved
    static func truncatedText(_ preview: String, originalSizeBytes: Int, sourceApp: String?) -> ClipboardItem {
        ClipboardItem(
            type: .text,
            sourceApp: sourceApp,
            textContent: preview,
            isTruncated: true,
            originalSizeBytes: originalSizeBytes
        )
    }
    
    /// Whether this item's full text is stored in a separate file
    var isFileBacked: Bool {
        textFilename != nil
    }
    
    /// Preview text for display (truncated for long content)
    var previewText: String {
        switch type {
        case .text:
            let text = textContent ?? ""
            if text.count > 200 {
                return String(text.prefix(200)) + "…"
            }
            return text
        case .image:
            return "Image"
        }
    }
    
    /// Content hash for duplicate detection
    var contentHash: Int {
        switch type {
        case .text:
            return textContent?.hashValue ?? 0
        case .image:
            return imageFilename?.hashValue ?? 0
        }
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}

enum ClipboardItemType: String, Codable {
    case text
    case image
}
