import AppKit
import Highlighter

/// Abstraction over a syntax-highlighting engine.
///
/// Views depend only on this protocol, never on HighlighterSwift directly, so the engine can
/// be swapped later (for example to a tree-sitter backend) without touching the UI layer.
protocol SyntaxHighlighting {
    /// The language names this engine can highlight, for populating a manual picker.
    func supportedLanguages() -> [String]

    /// Produce a highlighted attributed string for `code`, or nil if highlighting is not
    /// possible or not warranted (caller falls back to plain monospaced text).
    ///
    /// - Parameters:
    ///   - code: the source text.
    ///   - language: a highlight.js language name to force; nil means auto-detect.
    ///   - fontSize: point size to render at (tracks the app's zoom scale).
    ///   - dark: whether the system is in dark appearance (selects the theme).
    func highlight(_ code: String, language: String?, fontSize: CGFloat, dark: Bool) -> NSAttributedString?
}

/// HighlighterSwift-backed implementation (highlight.js under the hood).
///
/// Thread-safety: `Highlighter` wraps a JavaScriptCore context and is not safe to touch from
/// multiple threads at once, so all access is serialized through a dedicated queue. Callers are
/// expected to invoke `highlight` off the main thread (see `SyntaxHighlightCache`).
final class HighlighterSwiftEngine: SyntaxHighlighting, @unchecked Sendable {

    /// Shared instance. Safe to use across threads: all engine access is serialized through
    /// an internal queue (`@unchecked Sendable` reflects that this is hand-verified, since the
    /// wrapped Highlighter/JSContext is not itself Sendable).
    static let shared = HighlighterSwiftEngine()

    /// Above this many bytes we never highlight - highlight.js tokenizing a multi-megabyte
    /// paste would hang the UI, and the preview for such content is the chunked plain-text
    /// loader anyway. 100 KB comfortably covers any real code snippet.
    static let maxHighlightBytes = 100_000

    private let lightTheme = "atom-one-light"
    private let darkTheme = "atom-one-dark"
    private let monoFontName = "Menlo-Regular"

    private let queue = DispatchQueue(label: "com.buffer.syntax-highlight")
    private let highlighter: Highlighter?
    private var currentThemeIsDark: Bool?
    private var cachedLanguages: [String]?

    init() {
        // Failable: nil if the bundled highlight.min.js or default theme is missing.
        self.highlighter = Highlighter()
    }

    func supportedLanguages() -> [String] {
        queue.sync {
            if let cached = cachedLanguages { return cached }
            let langs = highlighter?.supportedLanguages().sorted() ?? []
            cachedLanguages = langs
            return langs
        }
    }

    func highlight(_ code: String, language: String?, fontSize: CGFloat, dark: Bool) -> NSAttributedString? {
        guard code.utf8.count <= Self.maxHighlightBytes else { return nil }

        return queue.sync {
            guard let highlighter = highlighter else { return nil }

            // Re-apply the theme only when appearance changes (setTheme reloads CSS, which is
            // not free). Font size is applied on every call since zoom can change independently.
            if currentThemeIsDark != dark {
                highlighter.setTheme(dark ? darkTheme : lightTheme)
                currentThemeIsDark = dark
            }
            let font = NSFont(name: monoFontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            highlighter.theme.setCodeFont(font)

            // Empty language string is treated as "no language" (auto-detect); nil also means auto.
            let langParam = (language?.isEmpty == false) ? language : nil
            return highlighter.highlight(code, as: langParam)
        }
    }
}

import SwiftUI

/// Builds an attributed string from a clipboard item's stored rich payload (RTFD, then RTF, then
/// HTML), so a combined text+image item renders with its images inline in their original position
/// and with its formatting - using the exact data that was captured, no reconstruction.
///
/// Network safety: NSAttributedString(html:) will fetch remote <img src="http..."> URLs while
/// parsing. To keep the preview offline, HTML is only used when it contains no remote image
/// references (inline base64 data: images are fine). RTFD/RTF embed their images and never fetch.
enum RichContentRenderer {

    /// Build an attributed string from the item's rich payload. `localImageURLs` are file URLs of
    /// images already downloaded for this item (combined-item attachments); when the HTML
    /// references remote images, their `src` is rewritten to these local files in order so the
    /// pictures render inline from disk - no network fetch during preview.
    static func attributedString(for item: ClipboardItem, fontSize: CGFloat, localImageURLs: [URL] = []) -> NSAttributedString? {
        if let rtfd = item.rtfdData,
           let s = NSAttributedString(rtfd: rtfd, documentAttributes: nil) {
            return normalizedForDarkablePane(s, fontSize: fontSize)
        }
        if let rtf = item.rtfData,
           let s = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            return normalizedForDarkablePane(s, fontSize: fontSize)
        }
        if let htmlData = item.htmlData {
            // If the HTML has remote images, only proceed when we can replace them with local
            // files (so nothing is fetched over the network); otherwise fall back.
            let resolvedHTML: Data?
            if htmlReferencesRemoteImages(htmlData) {
                resolvedHTML = localImageURLs.isEmpty
                    ? nil
                    : rewriteRemoteImagesToLocal(htmlData, localImageURLs: localImageURLs)
            } else {
                resolvedHTML = htmlData
            }
            if let html = resolvedHTML {
                let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ]
                if let s = try? NSAttributedString(data: html, options: options, documentAttributes: nil) {
                    return normalizedForDarkablePane(s, fontSize: fontSize)
                }
            }
        }
        return nil
    }

    /// Strip source-document colors so the content sits cleanly on Buffer's own pane:
    /// - Remove background colors (otherwise copied-from-web text shows its page background,
    ///   which reads as a highlight on the preview's dark pane).
    /// - Replace explicit foreground colors with the control's label color so text stays readable
    ///   in both light and dark appearance. Images (text attachments) are left untouched.
    private static func normalizedForDarkablePane(_ input: NSAttributedString, fontSize: CGFloat) -> NSAttributedString {
        let output = NSMutableAttributedString(attributedString: input)
        let full = NSRange(location: 0, length: output.length)
        output.removeAttribute(.backgroundColor, range: full)
        // Force the whole string to the control's label color so text is readable on the pane in
        // both light and dark appearance. Source HTML often leaves text with no explicit color,
        // which would otherwise render black (invisible on the dark pane). Attachment runs (images)
        // ignore foreground color, so this is safe to apply across the full range.
        output.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        // Match the plain-text preview: use the same monospaced system font and size on every
        // text run. Image attachment runs are left untouched so inline pictures keep their size.
        let monoFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        output.enumerateAttribute(.attachment, in: full) { value, range, _ in
            if value == nil {
                output.addAttribute(.font, value: monoFont, range: range)
            }
        }
        // Style hyperlinks as classic blue + underline so they stand out within the text, the way
        // they appear in the source. Applied AFTER the label-color pass so links are not flattened.
        output.enumerateAttribute(.link, in: full) { value, range, _ in
            guard value != nil else { return }
            output.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
            output.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        // Give image attachments a real display size. NSAttributedString(html:) loads the image
        // but leaves bounds at zero, so inline images would be invisible. Size each to its image's
        // natural dimensions, scaled down to fit a sensible preview width.
        let maxImageWidth: CGFloat = 480
        output.enumerateAttribute(.attachment, in: full) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            let image = attachment.image
                ?? attachment.fileWrapper?.regularFileContents.flatMap { NSImage(data: $0) }
            guard let img = image, img.size.width > 0, img.size.height > 0 else { return }
            if attachment.image == nil { attachment.image = img }
            var w = img.size.width
            var h = img.size.height
            if w > maxImageWidth {
                let scale = maxImageWidth / w
                w = maxImageWidth
                h = (h * scale).rounded()
            }
            attachment.bounds = NSRect(x: 0, y: 0, width: w, height: h)
            _ = range
        }
        return output
    }

    /// Replace each remote (http/https) <img src> in the HTML with a local file URL, in order,
    /// drawing from `localImageURLs`. Non-remote srcs (data:, already-local) are left as-is.
    /// Once the local images run out, remaining remote imgs are dropped (src emptied) so no
    /// network fetch happens. Returns the rewritten HTML as UTF-8 data.
    private static func rewriteRemoteImagesToLocal(_ html: Data, localImageURLs: [URL]) -> Data? {
        var text = String(decoding: html, as: UTF8.self)
        guard let regex = try? NSRegularExpression(
            pattern: "(<img\\b[^>]*?\\bsrc\\s*=\\s*[\"'])([^\"']+)([\"'][^>]*>)",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }

        // Work right-to-left so replacement ranges stay valid as we mutate the string.
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var localIndex = 0
        // Pre-scan left-to-right to assign a local file to each remote img in document order.
        var assignments: [(range: NSRange, replacement: String)] = []
        for m in matches {
            let src = ns.substring(with: m.range(at: 2))
            let lower = src.lowercased()
            guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { continue }
            let prefix = ns.substring(with: m.range(at: 1))
            let suffix = ns.substring(with: m.range(at: 3))
            let newSrc: String
            if localIndex < localImageURLs.count {
                newSrc = localImageURLs[localIndex].absoluteString
                localIndex += 1
            } else {
                newSrc = ""   // no local image left; blank the src so nothing is fetched
            }
            assignments.append((m.range, prefix + newSrc + suffix))
        }
        // Apply right-to-left.
        let mutable = NSMutableString(string: text)
        for a in assignments.reversed() {
            mutable.replaceCharacters(in: a.range, with: a.replacement)
        }
        text = mutable as String
        return text.data(using: .utf8)
    }

    /// True if the HTML contains an <img> whose src is a remote http(s) URL (would trigger a
    /// network fetch during parsing). Inline data: images and no images are both safe.
    private static func htmlReferencesRemoteImages(_ html: Data) -> Bool {
        let text = String(decoding: html, as: UTF8.self)
        guard let regex = try? NSRegularExpression(
            pattern: "<img\\b[^>]*?\\bsrc\\s*=\\s*[\"']([^\"']+)[\"']",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        var remote = false
        regex.enumerateMatches(in: text, range: range) { match, _, stop in
            guard let match = match, match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: text) else { return }
            let src = String(text[r])
            if src.hasPrefix("http://") || src.hasPrefix("https://") {
                remote = true
                stop.pointee = true
            }
        }
        return remote
    }
}

/// Read-only, selectable NSTextView host for a highlighted NSAttributedString.
///
/// SwiftUI `Text` cannot render an arbitrary NSAttributedString with per-token colors, so a
/// lightweight NSTextView is wrapped instead. It is non-editable but selectable, matching the
/// `.textSelection(.enabled)` behavior of the plain-text branch it replaces.
struct HighlightedTextView: NSViewRepresentable {
    let attributedText: NSAttributedString
    /// Active search query to highlight within the rendered text (empty = none).
    var searchQuery: String = ""

    func makeNSView(context: Context) -> NSTextView {
        // Build the TextKit stack explicitly. A bare NSTextView() does not lay out reliably
        // when embedded in SwiftUI (it can collapse to zero height), so the text container and
        // layout manager are wired up by hand with width tracking enabled.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = NSTextView(frame: NSRect.zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize.zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        // Make embedded links clickable and styled as classic blue underlined links.
        textView.isAutomaticLinkDetectionEnabled = false   // use only the links present in the markup
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        // Hug content vertically so SwiftUI gives it exactly the height the text needs.
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        let display = NSMutableAttributedString(attributedString: attributedText)
        applySearchHighlight(on: display)
        textView.textStorage?.setAttributedString(display)
        // Collapse any selection so the content is not shown with a highlighted background.
        // Setting the text can leave the whole string selected, which reads as "selected text".
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.invalidateIntrinsicContentSize()
    }

    /// Overlay a yellow background on every case-insensitive occurrence of the search query, so
    /// matches are visible even in syntax-highlighted or rich (image-bearing) content.
    private func applySearchHighlight(on text: NSMutableAttributedString) {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard query.count >= 1 else { return }
        let haystack = text.string
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: query, options: .caseInsensitive, range: searchRange) {
            let nsRange = NSRange(found, in: haystack)
            text.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.5), range: nsRange)
            text.addAttribute(.foregroundColor, value: NSColor.black, range: nsRange)
            searchRange = found.upperBound..<haystack.endIndex
        }
    }

    /// Report the laid-out height for the available width so the preview shows the full snippet
    /// instead of collapsing. Width comes from the SwiftUI-proposed size.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let width: CGFloat = proposal.width ?? nsView.bounds.width
        guard width > 0, let layoutManager = nsView.layoutManager, let container = nsView.textContainer else {
            return nil
        }
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        return CGSize(width: width, height: ceil(used.height))
    }
}
