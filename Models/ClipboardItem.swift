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

    /// Detect URLs in text using NSDataDetector, but only when the original text wrote an explicit
    /// scheme (`http://`, `https://`, `mailto:`). This is deliberately stricter than the detector,
    /// which happily synthesizes `http://` for a bare host like `current.id` or `entries.at` - in
    /// source code those are property accesses and method calls, not links. Requiring the scheme
    /// to be present in the source keeps real pasted URLs while rejecting those false positives.
    /// Pure, no network.
    static func detectURLs(in text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var urls: [String] = []
        var seen = Set<String>()
        detector.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match, let url = match.url else { return }
            let scheme = url.scheme?.lowercased()
            guard scheme == "http" || scheme == "https" || scheme == "mailto" else { return }
            // Only accept the match if the scheme was actually written in the source substring,
            // not inferred by the detector. Rejects bare hostnames like "current.id".
            let matched = nsText.substring(with: match.range).lowercased()
            guard matched.hasPrefix("http://")
                || matched.hasPrefix("https://")
                || matched.hasPrefix("mailto:") else { return }
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

/// Detects and parses tab-separated tabular text (as produced when a table is copied from Notion,
/// a spreadsheet, or a web page) so the preview can render it as an aligned grid instead of ragged
/// monospaced text. Pure, no side effects.
///
/// Detection is deliberately conservative to avoid turning ordinary prose or code that happens to
/// contain a stray tab into a "table": it requires multiple rows, at least two columns, and a
/// consistent column count across most rows.
enum TableDetector {
    /// A parsed table: the rows, each a list of cell strings. All rows are padded to the same
    /// column count so the renderer can lay out a rectangular grid.
    struct Table: Equatable {
        let rows: [[String]]
        var columnCount: Int { rows.first?.count ?? 0 }
    }

    /// Upper bounds so a pathological paste cannot produce an enormous grid. Beyond these the text
    /// falls back to the normal plain-text preview.
    static let maxRows = 200
    static let maxColumns = 20

    /// Parse `text` as a tab-separated table, or nil when it does not look like one. A nil result
    /// means the caller should render the text normally.
    ///
    /// Two strategies, tried in order:
    /// 1. Clean grid: every physical line is already one row with the same column count. This is
    ///    the common case for Notion and spreadsheet copies.
    /// 2. Header-driven reflow: the header establishes N columns but some cells contain embedded
    ///    newlines (seen with tables copied from Teams), so one logical row is spread across
    ///    several physical lines. Stitch physical lines back into N-column rows.
    static func parse(_ text: String) -> Table? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains("\t") else { return nil }

        let lines = trimmed.components(separatedBy: .newlines)
        // Keep interior lines even when blank, because a blank physical line can be the middle of
        // a multi-line cell. Only a hard cap guards against pathological input.
        guard lines.count >= 2, lines.count <= maxRows else { return nil }

        if let clean = parseCleanGrid(lines) { return clean }
        return parseWithHeaderReflow(lines)
    }

    /// Strategy 1: every non-empty physical line is already a complete row. Returns nil if the
    /// lines are not consistently columnar.
    private static func parseCleanGrid(_ lines: [String]) -> Table? {
        let rows = lines.filter { !$0.isEmpty }.map { $0.components(separatedBy: "\t") }
        guard rows.count >= 2 else { return nil }
        let counts = rows.map { $0.count }
        guard let maxCount = counts.max(), maxCount >= 2, maxCount <= maxColumns else { return nil }

        let modeCount = counts.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
        guard let (dominantColumns, dominantRows) = modeCount.max(by: { $0.value < $1.value }),
              dominantColumns >= 2,
              Double(dominantRows) / Double(rows.count) >= 0.9 else {
            // 0.9 (not 0.6): the clean path demands near-uniform rows. Anything messier is left to
            // the reflow path, which understands multi-line cells.
            return nil
        }

        return Table(rows: rows.map { normalize($0, to: dominantColumns) })
    }

    /// Strategy 2: trust the first line as an N-column header, then merge following physical lines
    /// into N-column logical rows, rejoining cells that were split by an embedded newline.
    private static func parseWithHeaderReflow(_ lines: [String]) -> Table? {
        let header = lines[0].components(separatedBy: "\t")
        let targetColumns = header.count
        guard targetColumns >= 2, targetColumns <= maxColumns else { return nil }

        // Only trust the header width if at least two later physical lines split into exactly that
        // many cells on their own. That is strong evidence the width is real, not coincidental.
        let bodyLines = lines.dropFirst().filter { !$0.isEmpty }
        let exactMatches = bodyLines.filter { $0.components(separatedBy: "\t").count == targetColumns }
        guard exactMatches.count >= 2 else { return nil }

        var rows: [[String]] = [header]
        var buffer: [String] = []

        for line in lines.dropFirst() {
            let cells = line.components(separatedBy: "\t")
            if buffer.isEmpty {
                buffer = cells
            } else {
                // The newline fell inside the last cell of the buffer, so the first fragment of
                // this line continues that cell. Join them (with a newline so cell content is
                // preserved verbatim), then append the remaining fragments as new cells.
                let joined = buffer[buffer.count - 1]
                    + "\n"
                    + (cells.first ?? "")
                buffer[buffer.count - 1] = joined
                buffer.append(contentsOf: cells.dropFirst())
            }

            if buffer.count >= targetColumns {
                rows.append(normalize(buffer, to: targetColumns))
                buffer = []
            }
        }
        if !buffer.isEmpty {
            rows.append(normalize(buffer, to: targetColumns))
        }

        // Require the reflow to have produced a plausible table: at least two body rows, and all
        // rows at the target width. Trim each cell so the stray leading tabs / blank fragments
        // introduced by the serialization do not show as empty lines.
        guard rows.count >= 3 else { return nil }
        let cleaned = rows.map { row in row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
        return Table(rows: cleaned)
    }

    /// Force `row` to exactly `columns` cells: pad short rows with empties, and fold any overflow
    /// cells into the last column (joined by tab) so no content is lost.
    private static func normalize(_ row: [String], to columns: Int) -> [String] {
        if row.count == columns { return row }
        if row.count < columns {
            return row + Array(repeating: "", count: columns - row.count)
        }
        let head = Array(row.prefix(columns - 1))
        let tail = row.suffix(from: columns - 1).joined(separator: "\t")
        return head + [tail]
    }
}
