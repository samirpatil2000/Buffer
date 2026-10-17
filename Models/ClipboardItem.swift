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

    // Rich-text flavours captured alongside the plain text (nil when absent or over the capture cap)
    var rtfData: Data?
    var htmlData: Data?

    // RTFD flavour, captured only as the resolution-2 fallback for when an item carries image
    // attachments: pasting .rtf alone does not preserve inline images (empirically verified,
    // see feature3-design.md section 4.8), so .rtfd is written first when present.
    var rtfdData: Data?

    // Images embedded alongside the text body, in document order (empty for pure text/image items)
    var imageFilenames: [String] = []

    // Manual syntax-highlighting language override for text items.
    // nil means auto-detect; "" (empty) means the user forced Plain Text (no highlighting).
    var language: String?

    // Hyperlinks extracted from the copied content's HTML/RTF (every <a href>), in document
    // order. Empty for plain copies with no links. Captured so a copied hyperlink is not
    // reduced to its visible text.
    var links: [WebLink] = []

    // Maps a remote image URL (as it appears in the stored HTML) to the local filename it was
    // downloaded into. Lets the preview rewrite remote <img> tags to the exact local file by URL,
    // so inline images render in the right place without a network fetch. Empty when no remote
    // images were downloaded.
    var remoteImageMap: [String: String] = [:]

    init(id: UUID = UUID(), type: ClipboardItemType, timestamp: Date = Date(), sourceApp: String? = nil, textContent: String? = nil, textFilename: String? = nil, imageFilename: String? = nil, isPinned: Bool = false, isBookmarked: Bool = false, tags: [String] = [], ocrText: String? = nil, isTruncated: Bool = false, originalSizeBytes: Int? = nil, rtfData: Data? = nil, htmlData: Data? = nil, rtfdData: Data? = nil, imageFilenames: [String] = [], language: String? = nil, links: [WebLink] = [], remoteImageMap: [String: String] = [:]) {
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
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.rtfdData = rtfdData
        self.imageFilenames = imageFilenames
        self.language = language
        self.links = links
        self.remoteImageMap = remoteImageMap
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, timestamp, sourceApp, textContent, textFilename, imageFilename
        case isPinned, isBookmarked, tags, ocrText, isTruncated, originalSizeBytes
        case rtfData, htmlData, rtfdData, imageFilenames, language, links, remoteImageMap
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
        self.rtfData = try container.decodeIfPresent(Data.self, forKey: .rtfData)
        self.htmlData = try container.decodeIfPresent(Data.self, forKey: .htmlData)
        self.rtfdData = try container.decodeIfPresent(Data.self, forKey: .rtfdData)
        self.imageFilenames = try container.decodeIfPresent([String].self, forKey: .imageFilenames) ?? []
        self.language = try container.decodeIfPresent(String.self, forKey: .language)
        self.links = try container.decodeIfPresent([WebLink].self, forKey: .links) ?? []
        self.remoteImageMap = try container.decodeIfPresent([String: String].self, forKey: .remoteImageMap) ?? [:]
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
        try container.encodeIfPresent(rtfData, forKey: .rtfData)
        try container.encodeIfPresent(htmlData, forKey: .htmlData)
        try container.encodeIfPresent(rtfdData, forKey: .rtfdData)
        if !imageFilenames.isEmpty { try container.encode(imageFilenames, forKey: .imageFilenames) }
        try container.encodeIfPresent(language, forKey: .language)
        if !links.isEmpty { try container.encode(links, forKey: .links) }
        if !remoteImageMap.isEmpty { try container.encode(remoteImageMap, forKey: .remoteImageMap) }
    }
    
    /// Create a text clipboard item
    static func text(_ content: String, sourceApp: String? = nil, rtfData: Data? = nil, htmlData: Data? = nil, rtfdData: Data? = nil) -> ClipboardItem {
        ClipboardItem(
            type: .text,
            sourceApp: sourceApp,
            textContent: content,
            rtfData: rtfData,
            htmlData: htmlData,
            rtfdData: rtfdData
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
    static func largeText(preview: String, filename: String, sourceApp: String? = nil, rtfData: Data? = nil, htmlData: Data? = nil, rtfdData: Data? = nil) -> ClipboardItem {
        ClipboardItem(
            type: .text,
            sourceApp: sourceApp,
            textContent: preview,
            textFilename: filename,
            rtfData: rtfData,
            htmlData: htmlData,
            rtfdData: rtfdData
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
        type == .text && !isFileBacked && !isTruncated && (textContent?.count ?? 0) <= 5000
    }

    /// Whether a styled representation of this item's text is available.
    /// Single consumer today is the row badge (Views/ClipboardItemRow.swift) - there is
    /// no detail-pane indicator in scope.
    var hasRichText: Bool { rtfData != nil || htmlData != nil }

    /// All image files this item owns, in a single list - the only correct input for
    /// file deletion and size accounting.
    var allImageFilenames: [String] {
        (imageFilename.map { [$0] } ?? []) + imageFilenames
    }

    /// True when the item carries at least one image, whether pure image or combined
    var hasImages: Bool { !allImageFilenames.isEmpty }

    /// True when the item carries both a text body and at least one image
    var isCombined: Bool { type == .text && !imageFilenames.isEmpty }

    /// Whether this item carries embedded image attachments (combined item), used by the
    /// row's second badge. Kept distinct from hasRichText (resolution 4) so the two can show
    /// simultaneously with visually distinct glyphs.
    var hasAttachedImages: Bool { !imageFilenames.isEmpty }

    /// Preview text for display (truncated for long content)
    var previewText: String {
        switch type {
        case .text:
            let text = textContent ?? ""
            if text.isEmpty {
                return imageFilenames.isEmpty ? "" : "Image"
            }
            if text.count > 200 {
                return String(text.prefix(200)) + "…"
            }
            return text
        case .image:
            return "Image"
        }
    }

    /// Header label shown in the detail pane
    var typeLabel: String {
        switch type {
        case .image: return "Image"
        case .text:
            guard !imageFilenames.isEmpty else { return "Text" }
            return imageFilenames.count == 1 ? "Text + Image" : "Text + \(imageFilenames.count) Images"
        }
    }
    
    /// Whether an item matches a search query, by text content or extracted OCR text.
    /// An empty ocrText (the auto-OCR no-text sentinel) deliberately never matches any
    /// non-empty query, so it cannot pollute search results.
    static func matches(item: ClipboardItem, query: String) -> Bool {
        if let textContent = item.textContent, textContent.localizedCaseInsensitiveContains(query) {
            return true
        }
        if let ocrText = item.ocrText, !ocrText.isEmpty, ocrText.localizedCaseInsensitiveContains(query) {
            return true
        }
        // Match on hyperlinks (captured, or detected live from the body for older items), by
        // both the visible anchor text and the URL itself.
        for link in item.effectiveLinks {
            if link.text.localizedCaseInsensitiveContains(query)
                || link.url.localizedCaseInsensitiveContains(query) {
                return true
            }
        }
        return false
    }

    /// Whether this item carries any hyperlinks (captured or detected from its text).
    var hasLinks: Bool { !effectiveLinks.isEmpty }

    /// The links to use for display, filtering, and search: the captured links when present,
    /// otherwise URLs detected live from the text body. This makes URL-bearing items captured
    /// before link detection existed behave like captured-link items, without altering storage.
    var effectiveLinks: [WebLink] {
        if !links.isEmpty { return links }
        guard type == .text, let text = textContent, !text.isEmpty else { return [] }
        return ClipboardItem.detectURLs(in: text).map { WebLink(text: $0, url: $0) }
    }

    /// Detect bare http(s)/mailto URLs in text using NSDataDetector. Pure, no network.
    static func detectURLs(in text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        var urls: [String] = []
        var seen = Set<String>()
        detector.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let url = match?.url else { return }
            let scheme = url.scheme?.lowercased()
            guard scheme == "http" || scheme == "https" || scheme == "mailto" else { return }
            let s = url.absoluteString
            guard !seen.contains(s) else { return }
            seen.insert(s)
            urls.append(s)
        }
        return urls
    }

    /// Whether this text item's content was detected as source code (used by the type filter).
    /// Computed on demand from the body; nil/empty text is never code.
    var looksLikeCode: Bool {
        guard type == .text, let text = textContent, !text.isEmpty else { return false }
        if case .code = LanguageDetector.detect(text) { return true }
        return false
    }

    /// Does this item belong to the given filter category? An item can match more than one
    /// category (e.g. a combined text+image item matches both Text and Image).
    func matchesKind(_ kind: ClipboardKind) -> Bool {
        switch kind {
        case .all:
            return true
        case .text:
            // Any item carrying a text body (plain text, or combined text+image).
            return type == .text && !(textContent ?? "").isEmpty
        case .image:
            return hasImages
        case .link:
            return hasLinks
        case .code:
            return looksLikeCode
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

/// A hyperlink extracted from copied rich content: the visible anchor text and its URL.
struct WebLink: Codable, Equatable {
    let text: String
    let url: String
}

/// A content category for filtering the history by type. An item may match several (for example
/// a combined text+image item is both `.text` and `.image`).
enum ClipboardKind: String, CaseIterable {
    case all
    case text
    case image
    case link
    case code

    /// Label for the filter chip.
    var label: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .image: return "Image"
        case .link: return "Link"
        case .code: return "Code"
        }
    }

    /// SF Symbol for the chip.
    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "doc.text"
        case .image: return "photo"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Parse a `type:` search token value (e.g. "image") into a kind, or nil if unrecognized.
    static func fromToken(_ value: String) -> ClipboardKind? {
        ClipboardKind(rawValue: value.lowercased())
    }
}
