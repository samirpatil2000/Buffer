import Foundation
import AppKit
import Combine

/// Manages persistent storage of clipboard history
class ClipboardStore: ObservableObject {
    @Published var items: [ClipboardItem] = []
    
    private func runOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
    
    private var maxItems: Int? { SettingsManager.shared.historyLimit.maxCount }
    private let fileManager = FileManager.default
    private let saveQueue = DispatchQueue(label: "com.buffer.save", qos: .utility)
    private var ocrInProgress: Set<UUID> = []
    
    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // Debug builds use a separate data directory so running from Xcode never
        // reads or overwrites the real release app's clipboard history.
        #if DEBUG
        let folderName = "Buffer-dev"
        #else
        let folderName = "Buffer"
        #endif
        return appSupport.appendingPathComponent(folderName, isDirectory: true)
    }
    
    private var historyFileURL: URL {
        storageDirectory.appendingPathComponent("history.json")
    }
    
    private var imagesDirectory: URL {
        storageDirectory.appendingPathComponent("images", isDirectory: true)
    }
    
    private var textsDirectory: URL {
        storageDirectory.appendingPathComponent("texts", isDirectory: true)
    }
    
    init() {
        ensureDirectoriesExist()
        loadHistory()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLimitChanged),
            name: .bufferHistoryLimitChanged,
            object: nil
        )
    }
    
    @objc private func handleLimitChanged() {
        guard let maxItems = maxItems, items.count > maxItems else { return }
        var trimmed = items
        while trimmed.count > maxItems {
            if let idx = trimmed.lastIndex(where: { !$0.isPinned && !$0.isBookmarked && $0.tags.isEmpty }) {
                deleteAssociatedFiles(for: trimmed[idx])
                trimmed.remove(at: idx)
            } else {
                break
            }
        }
        items = trimmed
        saveQueue.async { [weak self] in self?.saveHistoryToDisk(trimmed) }
    }
    
    // MARK: - Public API
    
    func add(_ item: ClipboardItem) {
        // Must be called on main thread for SwiftUI updates
        if Thread.isMainThread {
            performAdd(item)
        } else {
            DispatchQueue.main.sync {
                performAdd(item)
            }
        }
    }
    
    static func duplicateInlineTextIndex(for item: ClipboardItem, in items: [ClipboardItem]) -> Int? {
        guard item.type == .text,
              !item.isFileBacked,
              item.imageFilenames.isEmpty,          // a combined item is never a duplicate of plain text
              let text = item.textContent else { return nil }

        return items.firstIndex {
            $0.type == .text && !$0.isFileBacked && $0.imageFilenames.isEmpty && $0.textContent == text
        }
    }

    private func performAdd(_ item: ClipboardItem) {
        print("[Buffer] Store: Adding item, current count: \(items.count)")

        // Promote an existing identical inline text item instead of storing a duplicate.
        if SettingsManager.shared.deduplicateHistory,
           let duplicateIndex = Self.duplicateInlineTextIndex(for: item, in: items) {
            deleteAssociatedFiles(for: item)   // no-op for anything the predicate can match today
            moveToTop(items[duplicateIndex])
            return
        }
        
        // Insert at beginning (newest first)
        items.insert(item, at: 0)
        
        // Evict oldest unprotected item if over limit
        if let maxItems = maxItems, items.count > maxItems {
            if let indexToRemove = items.lastIndex(where: { !$0.isPinned && !$0.isBookmarked && $0.tags.isEmpty }) {
                let removed = items.remove(at: indexToRemove)
                deleteAssociatedFiles(for: removed)
            } else {
                // All items are protected — remove the oldest one anyway
                let removed = items.removeLast()
                deleteAssociatedFiles(for: removed)
            }
        }
        
        print("[Buffer] Store: New count: \(items.count)")
        
        // Save to disk in background
        let itemsToSave = items
        saveQueue.async { [weak self] in
            self?.saveHistoryToDisk(itemsToSave)
        }

        triggerAutoOCRIfNeeded(for: item)
    }

    /// Automatically run OCR on a freshly added item's image(s), if auto-OCR is enabled and the
    /// item hasn't been OCR'd yet. Covers pure image items (both capture paths) AND combined
    /// text+image items, which carry their pictures in `imageFilenames`. For a combined item the
    /// OCR text is stored separately in `ocrText` for search/retrieval - it is never merged into
    /// the item's own text and never affects what gets pasted.
    private func triggerAutoOCRIfNeeded(for item: ClipboardItem) {
        guard SettingsManager.shared.autoOCR,
              item.ocrText == nil,
              !ocrInProgress.contains(item.id) else { return }

        // Collect every image this item owns (pure image's single file, or a combined item's
        // attachment list). Nothing to OCR if there are no images.
        let filenames = item.allImageFilenames
        guard !filenames.isEmpty else { return }

        ocrInProgress.insert(item.id)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let images = filenames.compactMap { self.attachedImage(filename: $0) }
            guard !images.isEmpty else {
                self.runOnMain { self.ocrInProgress.remove(item.id) }
                return
            }

            Task {
                // OCR each image; join non-empty results with blank lines so multiple pictures
                // remain individually searchable.
                var pieces: [String] = []
                for image in images {
                    if let recognized = await OCRService.shared.recognizeText(from: image),
                       !recognized.isEmpty {
                        pieces.append(recognized)
                    }
                }
                // Empty string is the auto-OCR no-text sentinel, deliberately distinct from
                // the manual button's human-facing "No text found in this image." string,
                // because that string is itself text that could spuriously match a search.
                let text = pieces.joined(separator: "\n\n")
                self.runOnMain {
                    self.setOCRText(text, for: item)
                    self.ocrInProgress.remove(item.id)
                }
            }
        }
    }
    
    func delete(_ item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            self.items.removeAll { $0.id == item.id }
            self.deleteAssociatedFiles(for: item)
            
            let itemsToSave = self.items
            self.saveQueue.async { [weak self] in
                self?.saveHistoryToDisk(itemsToSave)
            }
        }
    }
    
    /// Delete multiple items in a single batch operation
    func delete(_ itemsToDelete: [ClipboardItem]) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            let ids = Set(itemsToDelete.map { $0.id })
            self.items.removeAll { ids.contains($0.id) }
            for item in itemsToDelete {
                self.deleteAssociatedFiles(for: item)
            }
            
            let itemsToSave = self.items
            self.saveQueue.async { [weak self] in
                self?.saveHistoryToDisk(itemsToSave)
            }
        }
    }
    
    /// Toggle pin state for an item
    func togglePin(for item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            self.items[index].isPinned.toggle()
            let itemsToSave = self.items
            self.saveQueue.async { [weak self] in self?.saveHistoryToDisk(itemsToSave) }
        }
    }

    /// Toggle bookmark state for an item (protected from eviction, stays in place)
    func toggleBookmark(for item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            self.items[index].isBookmarked.toggle()
            let itemsToSave = self.items
            self.saveQueue.async { [weak self] in self?.saveHistoryToDisk(itemsToSave) }
        }
    }
    
    /// Update text content for an editable text item
    func updateText(_ text: String, for item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            self.items[index].textContent = text
            self.items[index].rtfData = nil
            self.items[index].htmlData = nil
            let itemsToSave = self.items
            self.saveQueue.async { [weak self] in self?.saveHistoryToDisk(itemsToSave) }
        }
    }
    
    var allTags: [String] {
        Array(Set(items.flatMap { $0.tags })).sorted()
    }

    func addTag(_ tag: String, to item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            guard !self.items[index].tags.contains(tag) else { return }
            self.items[index].tags.append(tag)
            let itemsToSave = self.items
            self.saveQueue.async { [weak self] in self?.saveHistoryToDisk(itemsToSave) }
        }
    }

    func removeTag(_ tag: String, from item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            self.items[index].tags.removeAll { $0 == tag }
            let itemsToSave = self.items
            self.saveQueue.async { [weak self] in self?.saveHistoryToDisk(itemsToSave) }
        }
    }

    /// Save extracted OCR text for an image item
    func setOCRText(_ text: String, for item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            self.items[index].ocrText = text
            
            let itemsToSave = self.items
            self.saveQueue.async { [weak self] in
                self?.saveHistoryToDisk(itemsToSave)
            }
        }
    }

    /// Set the manual syntax-highlighting language override for a text item.
    /// Pass nil for auto-detect, "" to force Plain Text, or a highlight.js language name.
    func setLanguage(_ language: String?, for item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            self.items[index].language = language

            let itemsToSave = self.items
            self.saveQueue.async { [weak self] in
                self?.saveHistoryToDisk(itemsToSave)
            }
        }
    }

    /// Move an item to the top of the list (most recent position)
    func moveToTop(_ item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            
            // Already at top, no need to move
            if index == 0 { return }
            
            // Remove from current position and insert at top
            let removed = self.items.remove(at: index)
            self.items.insert(removed, at: 0)
            
            // Save updated order to disk
            let itemsToSave = self.items
            self.saveQueue.async { [weak self] in
                self?.saveHistoryToDisk(itemsToSave)
            }
        }
    }
    
    func clear(keepProtected: Bool = false) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            if keepProtected {
                let itemsToDelete = self.items.filter { !$0.isPinned && !$0.isBookmarked && $0.tags.isEmpty }
                for item in itemsToDelete {
                    self.deleteAssociatedFiles(for: item)
                }
                self.items.removeAll { !$0.isPinned && !$0.isBookmarked && $0.tags.isEmpty }
            } else {
                for item in self.items {
                    self.deleteAssociatedFiles(for: item)
                }
                self.items.removeAll()
            }
            
            let itemsToSave = self.items
            self.saveQueue.async { [weak self] in
                self?.saveHistoryToDisk(itemsToSave)
            }
        }
    }
    
    func image(for item: ClipboardItem) -> NSImage? {
        guard item.type == .image, let filename = item.imageFilename else { return nil }
        let url = imagesDirectory.appendingPathComponent(filename)
        return NSImage(contentsOf: url)
    }

    func attachedImage(filename: String) -> NSImage? {
        NSImage(contentsOf: imagesDirectory.appendingPathComponent(filename))
    }

    /// File URLs for an item's attachment images, in order. Used to render remote-image HTML
    /// inline by pointing <img> tags at these local files instead of fetching over the network.
    func attachedImageURLs(for item: ClipboardItem) -> [URL] {
        item.imageFilenames.map { imagesDirectory.appendingPathComponent($0) }
    }

    /// Images embedded in a combined item, in document order
    func attachedImages(for item: ClipboardItem) -> [NSImage] {
        item.imageFilenames.compactMap { attachedImage(filename: $0) }
    }

    /// Every image an item owns - pure image first, then attachments. For paste and export.
    func allImages(for item: ClipboardItem) -> [NSImage] {
        item.allImageFilenames.compactMap { attachedImage(filename: $0) }
    }

    /// Representative image for thumbnails and the detail preview
    func primaryImage(for item: ClipboardItem) -> NSImage? {
        guard let first = item.allImageFilenames.first else { return nil }
        return attachedImage(filename: first)
    }

    /// Remove image files written during a capture that did not complete. Not for live items -
    /// those go through deleteAssociatedFiles(for:).
    func removeImageFiles(_ filenames: [String]) {
        for name in filenames {
            try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(name))
        }
    }
    
    func saveImage(_ data: Data) -> String? {
        let filename = UUID().uuidString + ".png"
        let url = imagesDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: url)
            return filename
        } catch {
            print("[Buffer] Failed to save image: \(error)")
            return nil
        }
    }
    
    /// Save large text to a file and return the filename
    func saveText(_ text: String) -> String? {
        let filename = UUID().uuidString + ".txt"
        let url = textsDirectory.appendingPathComponent(filename)
        
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return filename
        } catch {
            print("[Buffer] Failed to save text file: \(error)")
            return nil
        }
    }
    
    /// Load full text content from file (lazy loading for large text)
    func fullText(for item: ClipboardItem) -> String? {
        guard let filename = item.textFilename else { return item.textContent }
        let url = textsDirectory.appendingPathComponent(filename)
        
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("[Buffer] Failed to load text file: \(error)")
            return item.textContent // Fallback to inline preview
        }
    }
    
    /// Load a chunk of text content, reading only what's necessary
    func textChunk(for item: ClipboardItem, charCount: Int) -> (text: String, totalBytes: Int, reachedEOF: Bool)? {
        if let filename = item.textFilename {
            // File-backed large text
            let url = textsDirectory.appendingPathComponent(filename)
            
            do {
                // Get total size from attributes without reading file
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let totalBytes = attributes[.size] as? Int ?? 0
                
                // Read a chunk that should contain enough characters
                // UTF-8 can be up to 4 bytes per character, so we read charCount * 4
                // to guarantee we have enough bytes for the requested characters
                let maximumBytesToRead = min(charCount * 4, totalBytes)
                
                let fileHandle = try FileHandle(forReadingFrom: url)
                defer { try? fileHandle.close() }
                
                let data = try fileHandle.read(upToCount: maximumBytesToRead) ?? Data()
                
                // Decode to string and take exact requested characters
                let fullChunkStr = String(decoding: data, as: UTF8.self)
                let exactChunkStr = String(fullChunkStr.prefix(charCount))
                
                // If the decoded string length is less than requested, we hit EOF
                let reachedEOF = fullChunkStr.count < charCount
                
                return (exactChunkStr, totalBytes, reachedEOF)
                
            } catch {
                print("[Buffer] Failed to read text chunk: \(error)")
                return nil
            }
        } else {
            // Inline text
            let content = item.textContent ?? ""
            let totalBytes = item.originalSizeBytes ?? content.utf8.count
            
            let prefix = String(content.prefix(charCount))
            let reachedEOF = content.count <= charCount
            
            return (prefix, totalBytes, reachedEOF)
        }
    }
    
    /// Get the total size of an item (in bytes) for UI display
    func itemSize(for item: ClipboardItem) -> Int? {
        if let original = item.originalSizeBytes {
            return original
        }
        
        switch item.type {
        case .text:
            let textBytes: Int
            if let filename = item.textFilename {
                let url = textsDirectory.appendingPathComponent(filename)
                textBytes = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
            } else {
                textBytes = item.textContent?.utf8.count ?? 0
            }
            let richBytes = (item.rtfData?.count ?? 0) + (item.htmlData?.count ?? 0) + (item.rtfdData?.count ?? 0)
            let total = textBytes + richBytes + imageFileBytes(for: item)
            return total > 0 ? total : nil
        case .image:
            let bytes = imageFileBytes(for: item)
            return bytes > 0 ? bytes : nil
        }
    }

    /// Sum of the on-disk size of every image file an item owns
    private func imageFileBytes(for item: ClipboardItem) -> Int {
        item.allImageFilenames.reduce(0) { total, filename in
            let url = imagesDirectory.appendingPathComponent(filename)
            let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
            return total + size
        }
    }
    
    // MARK: - Private
    
    private func ensureDirectoriesExist() {
        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: textsDirectory, withIntermediateDirectories: true)
    }
    
    private func loadHistory() {
        guard fileManager.fileExists(atPath: historyFileURL.path) else { 
            print("[Buffer] No history file found")
            return 
        }
        
        do {
            let data = try Data(contentsOf: historyFileURL)
            let loadedItems = try JSONDecoder().decode([ClipboardItem].self, from: data)
            self.items = loadedItems
            print("[Buffer] Loaded \(loadedItems.count) items from history")
        } catch {
            print("[Buffer] Failed to load history: \(error)")
        }
    }
    
    private func saveHistoryToDisk(_ itemsToSave: [ClipboardItem]) {
        do {
            let data = try JSONEncoder().encode(itemsToSave)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            print("[Buffer] Failed to save history: \(error)")
        }
    }
    
    private func deleteImageFiles(for item: ClipboardItem) {
        for filename in item.allImageFilenames {
            try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(filename))
        }
    }
    
    private func deleteTextFile(for item: ClipboardItem) {
        guard let filename = item.textFilename else { return }
        let url = textsDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
    }
    
    /// Delete all associated files (images and text files) for an item
    private func deleteAssociatedFiles(for item: ClipboardItem) {
        deleteImageFiles(for: item)
        deleteTextFile(for: item)
    }
}
