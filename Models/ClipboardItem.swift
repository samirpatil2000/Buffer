import Foundation
import AppKit

/// Structured "where did this come from" metadata for a clipboard item.
///
/// The fields are all optional and best-effort. Browser context is captured only
/// for supported browsers via Apple Events, and full URLs are intentionally not
/// stored — only the normalized host/domain and a truncated page title.
struct SourceContext: Codable, Equatable {
    /// Localized application name (e.g. "Notes", "Safari", "Arc").
    let appName: String?
    /// Bundle identifier of the source app (e.g. "com.apple.Safari").
    let appBundleID: String?
    /// Normalized host (e.g. "github.com"), present only for browser captures.
    let domain: String?
    /// Truncated page title for browser captures.
    let pageTitle: String?
    
    init(appName: String? = nil, appBundleID: String? = nil, domain: String? = nil, pageTitle: String? = nil) {
        self.appName = appName
        self.appBundleID = appBundleID
        self.domain = domain
        self.pageTitle = pageTitle
    }
    
    /// True when we successfully resolved a browser tab for this capture.
    var hasBrowserContext: Bool {
        domain != nil
    }
    
    /// True when the context contains nothing useful to display.
    var isEmpty: Bool {
        appName == nil && domain == nil
    }
    
    /// Compact label for the list row badge.
    /// Browser → domain. Otherwise → app name. Empty string if neither is known.
    var listLabel: String {
        if let domain = domain { return domain }
        return appName ?? ""
    }
    
    /// Detail line, e.g. "github.com · Pull request review" or "Notes".
    var detailLabel: String {
        if let domain = domain {
            if let title = pageTitle, !title.isEmpty {
                return "\(domain) · \(title)"
            }
            return domain
        }
        return appName ?? ""
    }
    
    /// Tooltip / accessibility hint, e.g. "Copied from github.com · Pull request review in Arc".
    var tooltip: String {
        if let domain = domain {
            var s = "Copied from \(domain)"
            if let title = pageTitle, !title.isEmpty {
                s += " · \(title)"
            }
            if let app = appName {
                s += " in \(app)"
            }
            return s
        }
        if let app = appName {
            return "Copied from \(app)"
        }
        return "Unknown source"
    }
}

/// Represents a single item in the clipboard history
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ClipboardItemType
    let timestamp: Date
    
    /// Legacy app-name field. Preserved so existing `history.json` files keep
    /// rendering after the upgrade. New items also fill it (mirroring
    /// `source.appName`) so a downgrade still shows something useful.
    let sourceApp: String?
    
    /// Structured source metadata captured at copy time. Optional and
    /// best-effort; nil for items written by older builds.
    let source: SourceContext?
    
    // For text items — inline content (nil for file-backed large text)
    let textContent: String?
    
    // For large text items — filename reference (stored separately, like images)
    let textFilename: String?
    
    // For image items — filename reference (stored separately)
    let imageFilename: String?
    
    // Bookmark state
    var isBookmarked: Bool
    
    // Pin state
    var isPinned: Bool = false
    
    // Extracted OCR text (persisted after first extraction)
    var ocrText: String?
    
    // For extreme text items — true if content exceeded storage limit and only preview is saved
    let isTruncated: Bool
    
    // For large/extreme text items — original size in bytes (for display purposes)
    let originalSizeBytes: Int?
    
    init(id: UUID = UUID(), type: ClipboardItemType, timestamp: Date = Date(), sourceApp: String? = nil, source: SourceContext? = nil, textContent: String? = nil, textFilename: String? = nil, imageFilename: String? = nil, isBookmarked: Bool = false, isPinned: Bool = false, ocrText: String? = nil, isTruncated: Bool = false, originalSizeBytes: Int? = nil) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.sourceApp = sourceApp ?? source?.appName
        self.source = source
        self.textContent = textContent
        self.textFilename = textFilename
        self.imageFilename = imageFilename
        self.isBookmarked = isBookmarked
        self.isPinned = isPinned
        self.ocrText = ocrText
        self.isTruncated = isTruncated
        self.originalSizeBytes = originalSizeBytes
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, timestamp, sourceApp, source, textContent, textFilename, imageFilename
        case isBookmarked, isPinned, ocrText, isTruncated, originalSizeBytes
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.type = try container.decode(ClipboardItemType.self, forKey: .type)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp)
        self.source = try container.decodeIfPresent(SourceContext.self, forKey: .source)
        self.textContent = try container.decodeIfPresent(String.self, forKey: .textContent)
        self.textFilename = try container.decodeIfPresent(String.self, forKey: .textFilename)
        self.imageFilename = try container.decodeIfPresent(String.self, forKey: .imageFilename)
        self.isBookmarked = try container.decodeIfPresent(Bool.self, forKey: .isBookmarked) ?? false
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
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
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(textContent, forKey: .textContent)
        try container.encodeIfPresent(textFilename, forKey: .textFilename)
        try container.encodeIfPresent(imageFilename, forKey: .imageFilename)
        try container.encode(isBookmarked, forKey: .isBookmarked)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(ocrText, forKey: .ocrText)
        try container.encode(isTruncated, forKey: .isTruncated)
        try container.encodeIfPresent(originalSizeBytes, forKey: .originalSizeBytes)
    }
    
    /// Returns the structured source if present, otherwise synthesizes one from the
    /// legacy `sourceApp` string so callers don't have to special-case old items.
    var effectiveSource: SourceContext? {
        if let source = source { return source }
        if let appName = sourceApp, !appName.isEmpty {
            return SourceContext(appName: appName)
        }
        return nil
    }
    
    /// Create a text clipboard item
    static func text(_ content: String, source: SourceContext? = nil) -> ClipboardItem {
        ClipboardItem(
            type: .text,
            source: source,
            textContent: content
        )
    }
    
    /// Create an image clipboard item
    static func image(filename: String, source: SourceContext? = nil) -> ClipboardItem {
        ClipboardItem(
            type: .image,
            source: source,
            imageFilename: filename
        )
    }
    
    /// Create a large text clipboard item (file-backed with inline preview)
    static func largeText(preview: String, filename: String, source: SourceContext? = nil) -> ClipboardItem {
        ClipboardItem(
            type: .text,
            source: source,
            textContent: preview,
            textFilename: filename
        )
    }
    
    /// Create an extremely large text item where only the preview is saved
    static func truncatedText(_ preview: String, originalSizeBytes: Int, source: SourceContext?) -> ClipboardItem {
        ClipboardItem(
            type: .text,
            source: source,
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
