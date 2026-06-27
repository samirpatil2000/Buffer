import Foundation
import AppKit

/// Represents a single item in the clipboard history
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ClipboardItemType
    let timestamp: Date
    let sourceApp: String?
    
    // For text items — inline content (nil for file-backed large text)
    var textContent: String?
    
    // For large text items — filename reference (stored separately, like images)
    let textFilename: String?
    
    // For image items — filename reference (stored separately)
    let imageFilename: String?
    
    // Pin state (protected + floats to top)
    var isPinned: Bool = false

    // Bookmark state (protected, stays in chronological position)
    var isBookmarked: Bool = false

    // User-defined tags
    var tags: [String] = []

    // Extracted OCR text (persisted after first extraction)
    var ocrText: String?
    
    // For extreme text items — true if content exceeded storage limit and only preview is saved
    let isTruncated: Bool
    
    // For large/extreme text items — original size in bytes (for display purposes)
    let originalSizeBytes: Int?
    
    init(id: UUID = UUID(), type: ClipboardItemType, timestamp: Date = Date(), sourceApp: String? = nil, textContent: String? = nil, textFilename: String? = nil, imageFilename: String? = nil, isPinned: Bool = false, isBookmarked: Bool = false, tags: [String] = [], ocrText: String? = nil, isTruncated: Bool = false, originalSizeBytes: Int? = nil) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.sourceApp = sourceApp
        self.textContent = textContent
        self.textFilename = textFilename
        self.imageFilename = imageFilename
        self.isPinned = isPinned
        self.isBookmarked = isBookmarked
        self.tags = tags
        self.ocrText = ocrText
        self.isTruncated = isTruncated
        self.originalSizeBytes = originalSizeBytes
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, timestamp, sourceApp, textContent, textFilename, imageFilename
        case isPinned, isBookmarked, tags, ocrText, isTruncated, originalSizeBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.type = try container.decode(ClipboardItemType.self, forKey: .type)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp)
        self.textContent = try container.decodeIfPresent(String.self, forKey: .textContent)
        self.textFilename = try container.decodeIfPresent(String.self, forKey: .textFilename)
        self.imageFilename = try container.decodeIfPresent(String.self, forKey: .imageFilename)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.isBookmarked = try container.decodeIfPresent(Bool.self, forKey: .isBookmarked) ?? false
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
        self.isTruncated = try container.decodeIfPresent(Bool.self, forKey: .isTruncated) ?? false
        self.originalSizeBytes = try container.decodeIfPresent(Int.self, forKey: .originalSizeBytes)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(sourceApp, forKey: .sourceApp)
        try container.encodeIfPresent(textContent, forKey: .textContent)
        try container.encodeIfPresent(textFilename, forKey: .textFilename)
        try container.encodeIfPresent(imageFilename, forKey: .imageFilename)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isBookmarked, forKey: .isBookmarked)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(ocrText, forKey: .ocrText)
        try container.encode(isTruncated, forKey: .isTruncated)
        try container.encodeIfPresent(originalSizeBytes, forKey: .originalSizeBytes)
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
    
    /// Whether this item is editable inline
    var isEditable: Bool {
        type == .text && !isFileBacked && !isTruncated
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
    
}

enum ClipboardItemType: String, Codable {
    case text
    case image
}
