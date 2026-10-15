import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

/// Monitors the system clipboard for changes and captures new content
class ClipboardWatcher: ObservableObject {
    @Published private(set) var isPaused = false
    
    private let store: ClipboardStore
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var lastContentHash: Int = 0
    private var ignoreNextChange = false
    
    private let pollInterval: TimeInterval = 0.5
    
    // Size thresholds for text handling
    private let inlineTextLimit = 50_000       // 50 KB — store inline
    private let previewLength = 500            // Characters kept as inline preview
    private let richTextLimit = 500_000        // 500 KB per flavour - larger payloads are dropped, plain text still captured

    // Combined-item capture budgets (section 4.3): bound attachment extraction cost and count
    private let maxEmbeddedImages = 8
    private let minEmbeddedImageEdge: CGFloat = 32   // POINTS, not pixels - filters visual noise, not resolution
    private let maxAttributedParseBytes = 10_000_000 // refuse to materialise a document larger than this
    private let maxAttachmentBytes = 5_000_000       // per attachment, measured on the PNG we would write

    // Cap how many hyperlinks a single copied item may store, so a large page cannot bloat it.
    private static let maxCapturedLinks = 50

    // Opt-in remote-image download budgets (only used when downloadRemoteImages is enabled).
    private let maxRemoteImageDownloads = 8          // cap how many URLs we fetch per copy
    private let remoteImageTimeout: TimeInterval = 5 // per-request timeout; copy must not hang
    private let maxRemoteImageBytes = 5_000_000      // reject responses larger than this

    static func shouldCaptureText(_ text: String, minimumLength: Int) -> Bool {
        !text.isEmpty && text.count >= minimumLength
    }
    
    init(store: ClipboardStore) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount
        
        // Listen for ignore notification (when copying from history)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleIgnoreNextChange),
            name: .bufferIgnoreNextChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleIgnoreNextChange() {
        ignoreNextChange = true
    }
    
    func startWatching() {
        guard timer == nil else { return }
        
        timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }
    
    func pause() {
        isPaused = true
    }
    
    func resume() {
        isPaused = false
        lastChangeCount = NSPasteboard.general.changeCount
    }
    
    private func checkClipboard() {
        guard !isPaused else { return }
        
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        
        // No change detected
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        
        // Skip if this is a copy from our own history
        if ignoreNextChange {
            ignoreNextChange = false
            return
        }
        
        // Get current frontmost app as source
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        
        // Check for single image file from Finder BEFORE text check
        // (Finder always writes both NSFilenamesPboardType + .string, so we must intercept first)
        if let filePaths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
           filePaths.count == 1,
           let filePath = filePaths.first {
            if isImageFile(filePath) {
                // Read and process image file asynchronously to avoid blocking the poll timer
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.processImageFile(filePath, sourceApp: sourceApp)
                }
                return  // Prevent .string branch from also processing this change
            }
        }
        
        // Try to capture text first
        if let text = pasteboard.string(forType: .string),
           Self.shouldCaptureText(text, minimumLength: SettingsManager.shared.minTextLength) {
            let rich = captureRichText(from: pasteboard)   // (rtf: Data?, html: Data?, rtfd: Data?)
            let textSize = text.utf8.count

            // Use prefix hash for large text to avoid expensive full-string hashing
            let hashSource = textSize > inlineTextLimit ? String(text.prefix(10_000)) : text

            // Raw attributed flavours, read on the main thread while the pasteboard is still current.
            // Not filtered by richTextLimit - that cap governs what we STORE. These are bounded instead
            // by maxAttributedParseBytes inside extractAttachments, which is where the cost actually is.
            let rtfdFlavour = SettingsManager.shared.preserveRichText ? pasteboard.data(forType: .rtfd) : nil
            let rtfFlavour = SettingsManager.shared.preserveRichText ? pasteboard.data(forType: .rtf) : nil

            // Capture hyperlinks (read on the main thread while the pasteboard is current).
            // Cheap synchronous string parsing, so it is computed once here and threaded into
            // whichever build path runs.
            let links = Self.captureLinks(from: pasteboard, rich: rich, plainText: text)

            // The async attachment path runs when there is a styled flavour to parse for embedded
            // images, OR when HTML is present and could yield images: inline base64 data: images
            // (always) or remote http(s) images (only if the user opted in). Browser copies have
            // HTML but no .rtf/.rtfd, so they would otherwise take the fast path and miss images.
            let htmlMayHaveImages = rich.html != nil
            if rtfdFlavour == nil && rtfFlavour == nil && !htmlMayHaveImages {
                // Fast path, identical to 3a: no attachments possible.
                let hash = hashSource.hashValue
                if hash != lastContentHash {
                    lastContentHash = hash
                    if let item = buildTextItem(text: text, sourceApp: sourceApp, rtf: rich.rtf, html: rich.html, rtfd: rich.rtfd, links: links) {
                        store.add(item)
                    }
                }
                return
            }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                // 1. Parse. No disk, no network. Bounded by maxAttributedParseBytes.
                var attachments = self.extractAttachments(rtfd: rtfdFlavour, rtf: rtfFlavour)

                // 1b. If no images were embedded via the attributed (.rtf/.rtfd) path, look at the
                //     HTML flavour. Browser copies carry images either as inline data: URIs
                //     (base64, already local - always extracted) or as remote http(s) URLs
                //     (fetched only when the user opted in to remote download).
                if attachments.isEmpty, let htmlData = rich.html {
                    let htmlString = String(decoding: htmlData, as: UTF8.self)
                    // Inline base64 images - no network, always safe to decode.
                    attachments = self.inlineDataImages(fromHTML: htmlString)
                    // Remote images - opt-in only, makes network requests.
                    if attachments.isEmpty, SettingsManager.shared.downloadRemoteImages {
                        attachments = self.downloadRemoteImages(fromHTML: htmlString)
                    }
                }

                // 2. Hash BEFORE any disk write, mixing attachment bytes so that the same caption
                //    copied twice with different pictures is not swallowed as a duplicate.
                let hash = attachments.isEmpty
                    ? hashSource.hashValue
                    : attachments.reduce(hashSource.hashValue) { $0 ^ $1.hashValue }

                // 3. Persist attachments.
                let filenames = attachments.compactMap { self.store.saveImage($0) }

                // 4. Build. On failure, roll back the files we just wrote.
                guard let item = self.buildTextItem(text: text, sourceApp: sourceApp, rtf: rich.rtf, html: rich.html, rtfd: rich.rtfd, imageFilenames: filenames, links: links) else {
                    self.removeImageFiles(filenames)
                    return
                }

                // 5. Gate + record + add, as one unit on the main thread.
                DispatchQueue.main.async {
                    guard hash != self.lastContentHash else {
                        self.removeImageFiles(filenames)     // rejected capture must not leak
                        return
                    }
                    self.lastContentHash = hash
                    self.store.add(item)
                }
            }
            return
        }
        
        // Try to capture image
        if let imageData = getImageData(from: pasteboard) {
            let hash = imageData.hashValue
            
            // Skip consecutive duplicates
            if hash != lastContentHash {
                lastContentHash = hash
                
                // Save image to disk
                if let filename = store.saveImage(imageData) {
                    let item = ClipboardItem.image(filename: filename, sourceApp: sourceApp)
                    store.add(item)
                }
            }
        }
    }
    
    /// Read the styled flavours of the current pasteboard, honouring the user setting and the size cap.
    /// .rtfd is captured only as the resolution-2 paste-fidelity fallback (images do not survive via
    /// .rtf's inline embedding, per feature3-design.md section 4.8) - it is not parsed here.
    private func captureRichText(from pasteboard: NSPasteboard) -> (rtf: Data?, html: Data?, rtfd: Data?) {
        guard SettingsManager.shared.preserveRichText else { return (nil, nil, nil) }
        return (capped(pasteboard.data(forType: .rtf), flavour: "rtf"),
                capped(pasteboard.data(forType: .html), flavour: "html"),
                capped(pasteboard.data(forType: .rtfd), flavour: "rtfd"))
    }

    private func capped(_ data: Data?, flavour: String) -> Data? {
        guard let data = data else { return nil }
        guard data.count <= richTextLimit else {
            print("[Buffer] Dropping \(flavour) flavour: \(data.count / 1024) KB exceeds cap")
            return nil
        }
        return data
    }

    /// Build a text item, choosing inline or file-backed storage by size. Returns nil only if the
    /// large-text file could not be written (matching today's behaviour of skipping the capture).
    private func buildTextItem(text: String, sourceApp: String?,
                                rtf: Data?, html: Data?, rtfd: Data? = nil,
                                imageFilenames: [String] = [],
                                links: [WebLink] = []) -> ClipboardItem? {
        let textSize = text.utf8.count
        if textSize <= inlineTextLimit {
            var item = ClipboardItem.text(text, sourceApp: sourceApp, rtfData: rtf, htmlData: html, rtfdData: rtfd)
            item.imageFilenames = imageFilenames
            item.links = links
            return item
        }
        guard let filename = store.saveText(text) else { return nil }
        print("[Buffer] Large text (\(textSize / 1024) KB) saved to file: \(filename)")
        var item = ClipboardItem.largeText(preview: String(text.prefix(previewLength)),
                                            filename: filename, sourceApp: sourceApp,
                                            rtfData: rtf, htmlData: html, rtfdData: rtfd)
        item.imageFilenames = imageFilenames
        item.links = links
        return item
    }

    /// Collect hyperlinks from the current copy: every <a href> in the HTML flavour, plus the
    /// single-URL pasteboard flavour (public.url) when the whole copy is one link that HTML did
    /// not already surface. Bounded to a sane maximum so a huge page cannot bloat an item.
    private static func captureLinks(from pasteboard: NSPasteboard,
                                     rich: (rtf: Data?, html: Data?, rtfd: Data?),
                                     plainText: String) -> [WebLink] {
        var links: [WebLink] = []

        if let htmlData = rich.html {
            let html = String(decoding: htmlData, as: UTF8.self)
            links = extractLinks(fromHTML: html)
        }

        // Single-URL flavour: present when you copy one link (e.g. a URL field or a "copy link"
        // action). Add it if the HTML did not already capture that URL.
        if let urlString = pasteboard.string(forType: NSPasteboard.PasteboardType("public.url"))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !urlString.isEmpty,
           !links.contains(where: { $0.url == urlString }) {
            // Use the plain text as the anchor label when it is short enough to be a caption.
            let label = plainText.count <= 200 ? plainText : urlString
            links.append(WebLink(text: label, url: urlString))
        }

        // Bare URLs typed/pasted as plain text (no HTML anchor, no URL flavour). Detect them so
        // a copied link is recognised even when it arrives as plain text.
        for detected in detectURLs(in: plainText) {
            if !links.contains(where: { $0.url == detected }) {
                links.append(WebLink(text: detected, url: detected))
            }
        }

        return Array(links.prefix(maxCapturedLinks))
    }

    /// Detect bare http(s) URLs in plain text using NSDataDetector. Returns absolute URL strings
    /// in order of appearance. Pure, no network. Exposed for unit testing.
    static func detectURLs(in text: String) -> [String] {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        var urls: [String] = []
        detector.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let url = match?.url else { return }
            let scheme = url.scheme?.lowercased()
            guard scheme == "http" || scheme == "https" || scheme == "mailto" else { return }
            urls.append(url.absoluteString)
        }
        return urls
    }

    /// Extract image attachments from an attributed pasteboard flavour. Never performs network I/O.
    private func extractAttachments(rtfd: Data?, rtf: Data?) -> [Data] {
        // Pick the preferred flavour that is small enough to parse. A flavour over the cap is not
        // a reason to fall back to a larger one, so both are tested against the same budget.
        let source: (data: Data, isRTFD: Bool)?
        if let rtfd = rtfd, rtfd.count <= maxAttributedParseBytes { source = (rtfd, true) }
        else if let rtf = rtf, rtf.count <= maxAttributedParseBytes { source = (rtf, false) }
        else { source = nil }

        guard let source = source else {
            if let oversized = rtfd ?? rtf {
                print("[Buffer] Skipping attachment extraction: attributed flavour is \(oversized.count / 1024) KB")
            }
            return []
        }

        let attributed = source.isRTFD
            ? NSAttributedString(rtfd: source.data, documentAttributes: nil)
            : NSAttributedString(rtf: source.data, documentAttributes: nil)
        guard let doc = attributed else { return [] }

        var out: [Data] = []
        doc.enumerateAttribute(.attachment, in: NSRange(location: 0, length: doc.length)) { value, _, stop in
            guard out.count < maxEmbeddedImages else { stop.pointee = true; return }
            guard let attachment = value as? NSTextAttachment else { return }
            let raw = attachment.fileWrapper?.regularFileContents
                ?? attachment.image?.tiffRepresentation
            guard let data = raw,
                  let image = NSImage(data: data),
                  image.size.width >= minEmbeddedImageEdge, image.size.height >= minEmbeddedImageEdge,
                  let png = Self.pngData(from: data),
                  png.count <= maxAttachmentBytes else { return }
            out.append(png)
        }
        if out.count >= maxEmbeddedImages {
            print("[Buffer] Capping embedded images at \(maxEmbeddedImages)")
        }
        return out
    }

    /// Decode inline base64 `data:image/...` URIs embedded in copied HTML into PNG data.
    /// No network - the bytes are already present in the HTML. Bounded by the same count and
    /// per-image size limits as other attachment paths.
    private func inlineDataImages(fromHTML html: String) -> [Data] {
        guard let regex = try? NSRegularExpression(
            pattern: "data:image/[a-zA-Z0-9.+-]+;base64,([A-Za-z0-9+/=]+)",
            options: [.caseInsensitive]
        ) else { return [] }

        let range = NSRange(html.startIndex..., in: html)
        var out: [Data] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: html, range: range) { match, _, stop in
            guard out.count < maxEmbeddedImages else { stop.pointee = true; return }
            guard let match = match, match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: html) else { return }
            let b64 = String(html[r])
            guard !seen.contains(b64), let raw = Data(base64Encoded: b64) else { return }
            seen.insert(b64)
            guard raw.count <= maxAttachmentBytes,
                  let image = NSImage(data: raw),
                  image.size.width >= minEmbeddedImageEdge, image.size.height >= minEmbeddedImageEdge,
                  let png = Self.pngData(from: raw) else { return }
            out.append(png)
        }
        if !out.isEmpty {
            print("[Buffer] Extracted \(out.count) inline data: image(s) from copied HTML")
        }
        return out
    }

    /// Extract hyperlinks (<a href="...">visible text</a>) from copied HTML. Pure string
    /// parsing, no network. Returns anchor text + URL pairs in document order, de-duplicated by
    /// (text, url). Only http(s) and mailto URLs are kept; fragment/relative/javascript anchors
    /// are skipped. Exposed for unit testing.
    static func extractLinks(fromHTML html: String) -> [WebLink] {
        guard let regex = try? NSRegularExpression(
            pattern: "<a\\b[^>]*?\\bhref\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }

        let range = NSRange(html.startIndex..., in: html)
        var links: [WebLink] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 3,
                  let hrefRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html) else { return }
            let url = String(html[hrefRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Keep only real, followable links.
            let lower = url.lowercased()
            guard lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:") else { return }
            // Strip inner HTML tags from the anchor text and decode a few common entities.
            let text = Self.strippedPlainText(String(html[textRange]))
            let key = text + "\u{1}" + url
            guard !seen.contains(key) else { return }
            seen.insert(key)
            links.append(WebLink(text: text, url: url))
        }
        return links
    }

    /// Remove HTML tags and decode a minimal set of entities from an anchor's inner text.
    private static func strippedPlainText(_ html: String) -> String {
        let noTags = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return noTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract absolute http(s) image URLs from copied HTML. Pure string parsing, no network.
    /// Exposed for unit testing. Relative URLs and data: URIs are ignored (data: images are
    /// already handled by the attributed-string attachment path).
    static func remoteImageURLs(fromHTML html: String) -> [URL] {
        // Match src="..." or src='...' inside <img ...> tags.
        guard let regex = try? NSRegularExpression(
            pattern: "<img\\b[^>]*?\\bsrc\\s*=\\s*[\"']([^\"']+)[\"']",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }

        let range = NSRange(html.startIndex..., in: html)
        var urls: [URL] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: html) else { return }
            let src = String(html[r])
            // Only absolute http(s) URLs - skip data:, relative, and other schemes.
            guard src.hasPrefix("http://") || src.hasPrefix("https://") else { return }
            guard !seen.contains(src), let url = URL(string: src) else { return }
            seen.insert(src)
            urls.append(url)
        }
        return urls
    }

    /// Download the remote images referenced in `html`, bounded by count, per-request timeout, and
    /// response size. Returns PNG-encoded data for each image that downloads and decodes cleanly.
    /// Runs synchronously on the calling background queue; never called on the main thread.
    private func downloadRemoteImages(fromHTML html: String) -> [Data] {
        let urls = Array(Self.remoteImageURLs(fromHTML: html).prefix(maxRemoteImageDownloads))
        guard !urls.isEmpty else { return [] }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = remoteImageTimeout
        config.httpCookieStorage = nil          // do not send stored cookies
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var out: [Data] = []
        for url in urls {
            let semaphore = DispatchSemaphore(value: 0)
            var pngResult: Data?
            let task = session.dataTask(with: url) { [weak self] data, response, _ in
                defer { semaphore.signal() }
                guard let self = self, let data = data else { return }
                guard data.count <= self.maxRemoteImageBytes else { return }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return }
                guard let image = NSImage(data: data),
                      image.size.width >= self.minEmbeddedImageEdge,
                      image.size.height >= self.minEmbeddedImageEdge,
                      let png = Self.pngData(from: data),
                      png.count <= self.maxAttachmentBytes else { return }
                pngResult = png
            }
            task.resume()
            // Bound the wait so a slow server cannot stall capture beyond the timeout.
            _ = semaphore.wait(timeout: .now() + remoteImageTimeout + 1)
            if let png = pngResult { out.append(png) }
        }
        if !out.isEmpty {
            print("[Buffer] Downloaded \(out.count) remote image(s) from copied HTML")
        }
        return out
    }

    /// Shared PNG re-encode used by both pasteboard-image capture and attachment extraction.
    private static func pngData(from data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
    }

    /// Remove image files written during a capture that did not complete. Not for live items -
    /// those go through ClipboardStore.deleteAssociatedFiles(for:).
    private func removeImageFiles(_ filenames: [String]) {
        guard !filenames.isEmpty else { return }
        store.removeImageFiles(filenames)
    }

    private func getImageData(from pasteboard: NSPasteboard) -> Data? {
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        
        for type in imageTypes {
            // Preserves today's raw-data fallback (`?? data`): without it, pasteboard images
            // that NSImage cannot round-trip stop being captured at all.
            if let data = pasteboard.data(forType: type) {
                return Self.pngData(from: data) ?? data
            }
        }
        
        return nil
    }
    
    /// Check if a file path points to an image by examining its UTType
    private func isImageFile(_ filePath: String) -> Bool {
        let fileExtension = (filePath as NSString).pathExtension.lowercased()
        guard !fileExtension.isEmpty else { return false }
        
        if let utType = UTType(filenameExtension: fileExtension) {
            return utType.conforms(to: .image)
        }
        return false
    }
    
    /// Read image file from disk, convert to PNG, and store as image item
    private func processImageFile(_ filePath: String, sourceApp: String?) {
        do {
            // Read file bytes
            let fileURL = URL(fileURLWithPath: filePath)
            let fileData = try Data(contentsOf: fileURL)
            
            // Convert to PNG using the same pattern as pasteboard image handling
            guard let pngData = Self.pngData(from: fileData) else {
                print("[Buffer] Failed to convert image file: \(filePath)")
                return
            }
            
            // Check for duplicate using hash
            let hash = pngData.hashValue
            guard hash != lastContentHash else {
                // print("[Buffer] Duplicate image file detected: \(filePath)")
                return
            }
            
            // Save image to disk and add to store
            if let filename = store.saveImage(pngData) {
                let item = ClipboardItem.image(filename: filename, sourceApp: sourceApp)
                DispatchQueue.main.async { [weak self] in
                    self?.lastContentHash = hash
                    self?.store.add(item)
                }
            }
        } catch {
            print("[Buffer] Error processing image file: \(filePath) - \(error)")
        }
    }
}
