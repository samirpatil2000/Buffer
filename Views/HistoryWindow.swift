import Cocoa
import SwiftUI

/// Custom panel that closes when clicking outside
class HistoryPanel: NSPanel {
    var onClickOutside: (() -> Void)?
    
    override var canBecomeKey: Bool { true }
    
    override func resignKey() {
        super.resignKey()
        onClickOutside?()
    }
}

private struct ChunkedTextState {
    var visibleText: String = ""
    var totalBytes: Int = 0
    var loadedCharCount: Int = 0
    var reachedEOF: Bool = true
    var isLoadingMore: Bool = false
    static let chunkSize = 2_000
    static let initialChars = 2_000
    var hasMore: Bool { !reachedEOF && loadedCharCount >= Self.initialChars }
}

/// Manages the floating history window
class HistoryWindowController: NSWindowController {
    private let store: ClipboardStore
    private var previousApp: NSRunningApplication?

    /// Timestamp of the last close — used to decide whether to persist search state
    private var lastClosedAt: Date?
    /// Shared flag: true if the content view should reset search on the next open
    var shouldResetOnOpen: Bool = true
    /// Last selected item UUID — restored when reopening within the threshold
    var savedSelectedID: UUID?

    /// Reset search if window was closed more than 1.5 minutes ago (or never opened)
    private var shouldResetSearch: Bool {
        guard let lastClosed = lastClosedAt else { return true }
        return Date().timeIntervalSince(lastClosed) > 90
    }

    init(store: ClipboardStore) {
        self.store = store
        
        // Wider window for split pane
        let panel = HistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 480),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: panel)
        
        panel.onClickOutside = { [weak self] in
            self?.close()
        }
        
        setupPanel(panel)
        setupContent()
    }

    override func close() {
        lastClosedAt = Date()
        super.close()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupPanel(_ panel: NSPanel) {
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 10
        panel.contentView?.layer?.masksToBounds = true
        
        panel.center()
        
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Notify content view when window becomes key so it can reset state
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .bufferWindowDidOpen, object: nil)
        }
    }
    
    private func setupContent() {
        let contentView = HistoryContentView(
            store: store,
            shouldResetOnOpen: Binding(
                get: { [weak self] in self?.shouldResetOnOpen ?? true },
                set: { [weak self] newValue in self?.shouldResetOnOpen = newValue }
            ),
            savedSelectedID: Binding(
                get: { [weak self] in self?.savedSelectedID },
                set: { [weak self] newValue in self?.savedSelectedID = newValue }
            ),
            onCopyToClipboard: { [weak self] item in
                self?.copyToClipboard(item)
            },
            onPaste: { [weak self] item in
                self?.pasteItem(item)
            },
            onPasteMultiple: { [weak self] items in
                self?.pasteMultiple(items)
            },
            onDismiss: { [weak self] in
                self?.close()
            }
        )
        
        window?.contentView = NSHostingView(rootView: contentView)
    }
    
    private func copyToClipboard(_ item: ClipboardItem) {
        NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
        PasteController.copyToClipboard(item, store: store)
    }
    
    private func pasteItem(_ item: ClipboardItem) {
        let appToRestore = previousApp
        close()
        NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
        PasteController.paste(item, store: store, previousApp: appToRestore)
    }
    
    private func pasteMultiple(_ items: [ClipboardItem]) {
        let appToRestore = previousApp
        close()
        NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
        PasteController.pasteMultiple(items, store: store, previousApp: appToRestore)
    }
    
    override func showWindow(_ sender: Any?) {
        previousApp = NSWorkspace.shared.frontmostApplication
        // Compute reset decision *before* super.showWindow fires didBecomeKeyNotification
        // → bufferWindowDidOpen, so the content view onReceive handler sees the right value.
        shouldResetOnOpen = shouldResetSearch
        window?.center()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(window?.contentView)
    }
}

extension Notification.Name {
    static let bufferIgnoreNextChange = Notification.Name("bufferIgnoreNextChange")
    static let bufferHotkeyChanged = Notification.Name("bufferHotkeyChanged")
    static let bufferWindowDidOpen = Notification.Name("bufferWindowDidOpen")
    static let bufferHistoryLimitChanged = Notification.Name("bufferHistoryLimitChanged")
}

/// Main content view - Split pane with list and detail
struct HistoryContentView: View {
    @ObservedObject var store: ClipboardStore
    /// Set to true by HistoryWindowController when the window has been closed for more than
    /// 1.5 minutes (or on the very first open). The view resets search/tag state only when this
    /// is true, then writes false back so a second notification in the same session is a no-op.
    @Binding var shouldResetOnOpen: Bool
    /// Last selected item UUID, kept in sync with selectedID and restored on reopen within
    /// the threshold. Stored on the controller so it survives SwiftUI state resets.
    @Binding var savedSelectedID: UUID?
    let onCopyToClipboard: (ClipboardItem) -> Void
    let onPaste: (ClipboardItem) -> Void
    let onPasteMultiple: ([ClipboardItem]) -> Void
    let onDismiss: () -> Void
    
    @FocusState private var isSearchFocused: Bool
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var selectedIndex = 0
    @State private var previewImage: NSImage?
    @State private var chunkedText = ChunkedTextState()
    @State private var scrollTrigger = false  // Triggers scroll on keyboard navigation
    @State private var itemSize: Int?         // Holds computed size of item
    
    // Multi-select state
    @State private var selectedIDs: Set<UUID> = []
    @State private var selectionAnchor: UUID?
    @State private var showDeleteConfirmation = false
    @State private var isDeleteHovered = false
    
    // OCR state
    @State private var isExtractingText = false

    // Tag filter state
    @State private var activeTagFilter: String? = nil
    @State private var showTagAutocomplete: Bool = false
    @State private var showTagInput: Bool = false
    @State private var tagInputText: String = ""
    @FocusState private var isTagInputFocused: Bool

    // Track selection by ID so it survives list insertions
    @State private var selectedID: UUID?
    
    // Editing state
    @State private var isEditing = false
    @State private var editText = ""
    @State private var editingItemID: UUID?
    @FocusState private var isTextEditorFocused: Bool
    
    @State private var filteredItems: [ClipboardItem] = []
    
    private func computeFilteredItems() -> [ClipboardItem] {
        var base = store.items
        if let tag = activeTagFilter {
            base = base.filter { $0.tags.contains(tag) }
        }
        let query = debouncedSearchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty && !query.hasPrefix("#") {
            base = base.filter { item in
                guard item.type == .text else { return false }
                return item.textContent?.localizedCaseInsensitiveContains(query) ?? false
            }
        }
        return base.sorted { $0.isPinned && !$1.isPinned }
    }
    
    private func updateFilteredItems() {
        self.filteredItems = computeFilteredItems()
    }

    private var tagSuggestions: [String] {
        let query = searchText.hasPrefix("#") ? String(searchText.dropFirst()).lowercased() : ""
        if query.isEmpty { return store.allTags }
        return store.allTags.filter { $0.hasPrefix(query) }
    }

    private func tagInputSuggestions(excluding existing: [String]) -> [String] {
        guard !tagInputText.isEmpty else { return [] }
        return store.allTags.filter { $0.hasPrefix(tagInputText.lowercased()) && !existing.contains($0) }
    }
    
    /// Get the first unpinned item, or the first pinned item if no unpinned items exist
    private var defaultSelectedItem: ClipboardItem? {
        return filteredItems.first(where: { !$0.isPinned }) ?? filteredItems.first
    }
    
    /// Get all selected items in filtered list order
    private var selectedItems: [ClipboardItem] {
        filteredItems.filter { selectedIDs.contains($0.id) }
    }
    
    /// Get the primary selected item (for detail pane when multiple selected or single item)
    /// Returns the first selected item in list order
    private var selectedItem: ClipboardItem? {
        selectedItems.first
    }
    
    /// Selection status for UI display
    private var selectionCount: Int {
        selectedIDs.count
    }
    
    /// Total size of all selected items
    private var selectedItemsTotalSize: Int {
        selectedItems.reduce(0) { sum, item in
            sum + (store.itemSize(for: item) ?? 0)
        }
    }
    
    // MARK: - Selection Helpers
    
    /// Select a single item (clears previous multi-selection)
    private func selectSingle(_ id: UUID) {
        selectedIDs = [id]
        selectionAnchor = id
        selectedID = id  // Explicitly set selectedID
        if let index = filteredItems.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        }
    }
    
    /// Toggle an item in multi-select (Cmd+click behavior)
    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        selectionAnchor = id
        if let index = filteredItems.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
            // selectedID will be synced via onChange(of: selectedIndex)
        }
    }
    
    /// Extend selection from anchor to target item (Shift+click behavior)
    private func extendSelectionTo(_ targetID: UUID) {
        guard let anchorID = selectionAnchor else {
            selectSingle(targetID)
            return
        }
        
        guard let anchorIndex = filteredItems.firstIndex(where: { $0.id == anchorID }),
              let targetIndex = filteredItems.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        
        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedIDs = Set(filteredItems[range].map { $0.id })
        selectedIndex = targetIndex
        // selectedID will be synced via onChange(of: selectedIndex)
    }
    
    /// Extend selection upward (Shift+↑ behavior)
    private func extendSelectionUp() {
        guard selectedIndex > 0 else { return }
        
        let currentItem = filteredItems[selectedIndex]
        let previousIndex = selectedIndex - 1
        let previousItem = filteredItems[previousIndex]
        
        if selectedIDs.isEmpty {
            selectSingle(currentItem.id)
            return
        }
        
        // If moving up, always include the new item
        selectedIDs.insert(previousItem.id)
        selectionAnchor = selectionAnchor ?? currentItem.id
        
        selectedIndex = previousIndex
        // selectedID will be synced via onChange(of: selectedIndex)
    }
    
    /// Extend selection downward (Shift+↓ behavior)
    private func extendSelectionDown() {
        guard selectedIndex < filteredItems.count - 1 else { return }
        
        let currentItem = filteredItems[selectedIndex]
        let nextIndex = selectedIndex + 1
        let nextItem = filteredItems[nextIndex]
        
        if selectedIDs.isEmpty {
            selectSingle(currentItem.id)
            return
        }
        
        // If moving down, always include the new item
        selectedIDs.insert(nextItem.id)
        selectionAnchor = selectionAnchor ?? currentItem.id
        
        selectedIndex = nextIndex
        // selectedID will be synced via onChange(of: selectedIndex)
    }
    
    /// Clear all selections
    private func clearSelection() {
        selectedIDs = []
        selectionAnchor = nil
        selectedID = nil
    }
    
    /// Download all selected images to a folder
    /// Download all selected images to a folder
    private func downloadAllImages() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.title = "Select Folder to Save Images"
        openPanel.prompt = "Select"
        
        // Use the newer sheet modal approach
        if let window = NSApplication.shared.windows.first {
            openPanel.beginSheetModal(for: window) { response in
                if response == .OK, let folderURL = openPanel.url {
                    DispatchQueue.global(qos: .userInitiated).async {
                        let imageItems = self.selectedItems.filter { $0.type == .image }
                        
                        for (index, item) in imageItems.enumerated() {
                            if let image = self.store.image(for: item) {
                                let paddedNumber = String(format: "%04d", index + 1)
                                let fileName = "image-\(paddedNumber).png"
                                let fileURL = folderURL.appendingPathComponent(fileName)
                                
                                if let tiffData = image.tiffRepresentation,
                                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                                   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                                    do {
                                        try pngData.write(to: fileURL)
                                        print("✅ Saved image to \(fileURL.lastPathComponent)")
                                    } catch {
                                        print("❌ Error saving image to \(fileURL): \(error)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar

            // Tag autocomplete (when typing #...)
            if showTagAutocomplete && !store.allTags.isEmpty {
                tagAutocompleteBar
            }

            Divider()

            // Split pane: List + Detail
            HSplitView {
                // Left: List
                listPane
                    .frame(minWidth: 280, maxWidth: 350)
                
                // Right: Detail
                detailPane
                    .frame(minWidth: 300)
            }
            
            Divider()
            
            // Bottom action bar
            actionBar
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: searchText) { newValue in
            showTagAutocomplete = newValue.hasPrefix("#")
            
            searchDebounceTask?.cancel()
            
            if newValue.isEmpty {
                // Instantly update when search text is cleared
                debouncedSearchText = newValue
            } else {
                searchDebounceTask = Task {
                    // 200ms debounce
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        debouncedSearchText = newValue
                    }
                }
            }
        }
        .onChange(of: debouncedSearchText) { newValue in
            let currentFiltered = computeFilteredItems()
            self.filteredItems = currentFiltered
            
            // Don't reset selection when in tag autocomplete mode (list is unchanged)
            guard !newValue.hasPrefix("#") else { return }
            // Find first unpinned item in filtered results
            let defaultItem = currentFiltered.first(where: { !$0.isPinned }) ?? currentFiltered.first
            selectedID = defaultItem?.id
            if let id = defaultItem?.id {
                selectedIDs = [id]
                selectionAnchor = id
            } else {
                selectedIDs = []
                selectionAnchor = nil
            }
            // Calculate the correct index
            if let index = currentFiltered.firstIndex(where: { $0.id == defaultItem?.id }) {
                selectedIndex = index
            } else {
                selectedIndex = 0
            }
        }
        .onChange(of: activeTagFilter) { _ in
            let currentFiltered = computeFilteredItems()
            self.filteredItems = currentFiltered
            
            // Reset selection to the first item of the new tag filter
            let defaultItem = currentFiltered.first(where: { !$0.isPinned }) ?? currentFiltered.first
            selectedID = defaultItem?.id
            if let id = defaultItem?.id {
                selectedIDs = [id]
                selectionAnchor = id
            } else {
                selectedIDs = []
                selectionAnchor = nil
            }
            if let index = currentFiltered.firstIndex(where: { $0.id == defaultItem?.id }) {
                selectedIndex = index
            } else {
                selectedIndex = 0
            }
        }
        .onChange(of: showTagInput) { newValue in
            if newValue {
                // Defer by one run loop so the TextField is in the hierarchy before focusing
                DispatchQueue.main.async { isTagInputFocused = true }
            } else {
                isTagInputFocused = false
            }
        }
        .onChange(of: selectedIndex) { newIndex in
            selectedID = filteredItems[safe: newIndex]?.id
        }
        .onChange(of: selectedID) { newValue in
            // Keep savedSelectedID in sync so the controller can restore it on next open
            savedSelectedID = newValue
        }
        .onChange(of: selectedItem?.id) { _ in
            if isEditing {
                exitEditMode()
            }
        }
        .onChange(of: store.items) { _ in
            let currentFiltered = computeFilteredItems()
            self.filteredItems = currentFiltered
            
            // Remove deleted items from selection set
            selectedIDs = selectedIDs.filter { id in
                currentFiltered.contains { $0.id == id }
            }
            
            // Preserve selection by UUID lookup, adjust index if needed
            guard let id = selectedID else { return }
            if let newIndex = currentFiltered.firstIndex(where: { $0.id == id }) {
                if selectedIndex != newIndex { selectedIndex = newIndex }
            } else {
                // Selected item was deleted — select the item now at the same position (or last)
                let fallbackIndex = min(selectedIndex, currentFiltered.count - 1)
                if let fallbackItem = currentFiltered[safe: fallbackIndex] {
                    selectedID = fallbackItem.id
                    selectedIDs = [fallbackItem.id]
                    selectionAnchor = fallbackItem.id
                    selectedIndex = fallbackIndex
                } else {
                    selectedID = nil
                    selectedIDs = []
                    selectionAnchor = nil
                    selectedIndex = 0
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bufferWindowDidOpen)) { _ in
            // Only reset persistent search state if the window was closed long enough ago
            // (or this is the first open). shouldResetOnOpen is set by the controller in
            // showWindow(_:) before the notification fires.
            if shouldResetOnOpen {
                searchText = ""
                debouncedSearchText = ""
                activeTagFilter = nil
            } else {
                debouncedSearchText = searchText
            }
            
            // Recalculate cache immediately
            let currentFiltered = computeFilteredItems()
            self.filteredItems = currentFiltered
            
            // Transient UI state always resets
            showTagAutocomplete = false
            showTagInput = false
            tagInputText = ""
            isEditing = false
            
            // Determine target selection:
            // • Within threshold + saved UUID still in filtered list → restore it
            // • Otherwise → first unpinned item (or first if all pinned)
            let targetID: UUID?
            if !shouldResetOnOpen,
               let saved = savedSelectedID,
               currentFiltered.contains(where: { $0.id == saved }) {
                targetID = saved
            } else {
                targetID = (currentFiltered.first(where: { !$0.isPinned }) ?? currentFiltered.first)?.id
            }
            selectedID = targetID
            if let id = targetID {
                selectedIDs = [id]
                selectionAnchor = id
            } else {
                selectedIDs = []
                selectionAnchor = nil
            }
            if let index = currentFiltered.firstIndex(where: { $0.id == targetID }) {
                selectedIndex = index
            } else {
                selectedIndex = 0
            }
            // Trigger scroll so ClipboardListView brings the selected row into view
            scrollTrigger = true
            // Delay needed for NSHostingView to have settled as key window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onAppear {
            updateFilteredItems()
        }
        .task(id: selectedItem?.id) {
            // Clear preview
            previewImage = nil
            chunkedText = ChunkedTextState()
            isExtractingText = false
            itemSize = nil
            showTagInput = false
            tagInputText = ""
            
            // Load new preview async
            if let item = selectedItem {
                itemSize = store.itemSize(for: item)
                
                if item.type == .image {
                    previewImage = await loadPreviewImage(for: item)
                } else if item.type == .text {
                    if item.isFileBacked || (item.textContent?.count ?? 0) > 5000 {
                        await loadInitialChunk(for: item)
                    } else {
                        chunkedText.visibleText = item.textContent ?? ""
                        chunkedText.reachedEOF = true
                    }
                }
            }
        }
        .background(GlobalKeyMonitor(
            isEditing: isEditing,
            onUp: {
                guard !isEditing else { return }
                scrollTrigger = true
                navigateUp()
            },
            onDown: {
                guard !isEditing else { return }
                scrollTrigger = true
                navigateDown()
            },
            onExtendUp: {
                guard !isEditing else { return }
                scrollTrigger = true
                extendSelectionUp()
            },
            onExtendDown: {
                guard !isEditing else { return }
                scrollTrigger = true
                extendSelectionDown()
            },
            onEnter: {
                if isEditing { return }
                if showTagInput {
                    if let item = selectedItem {
                        let normalized = TagChip.normalize(tagInputText)
                        if !normalized.isEmpty { store.addTag(normalized, to: item) }
                    }
                    tagInputText = ""
                    showTagInput = false
                } else if searchText.hasPrefix("#") {
                    let tagQuery = String(searchText.dropFirst()).trimmingCharacters(in: .whitespaces)
                    if let match = store.allTags.first(where: { $0 == tagQuery }) ?? store.allTags.first(where: { $0.hasPrefix(tagQuery) }) {
                        activeTagFilter = match
                        searchText = ""
                        showTagAutocomplete = false
                    }
                } else if !selectedItems.isEmpty {
                    onPasteMultiple(Array(selectedItems))
                } else if let item = selectedItem {
                    onPaste(item)
                }
            },
            onEscape: {
                if isEditing {
                    exitEditMode()
                    return
                }
                if showTagInput {
                    showTagInput = false
                    tagInputText = ""
                } else {
                    onDismiss()
                }
            },
            onDelete: {
                guard !isEditing else { return }
                if let item = selectedItem {
                    store.delete(item)
                }
            },
            onCopy: {
                guard !isEditing else { return }
                if let item = selectedItem { onCopyToClipboard(item) }
            },
            onPin: {
                guard !isEditing else { return }
                if let item = selectedItem {
                    store.togglePin(for: item)
                }
            },
            onBookmark: {
                guard !isEditing else { return }
                if let item = selectedItem {
                    store.toggleBookmark(for: item)
                }
            },
            onSaveImage: {
                guard !isEditing else { return }
                if selectedItem?.type == .image, let img = previewImage {
                    PasteController.saveImageToDisk(img)
                }
            },
            onAddTag: {
                guard !isEditing else { return }
                guard selectedItem != nil else { return }
                showTagInput = true
            },
            onTabComplete: {
                guard !isEditing else { return }
                if showTagInput {
                    guard !tagInputText.isEmpty, let item = selectedItem else { return }
                    let suggestions = store.allTags.filter {
                        $0.hasPrefix(tagInputText.lowercased()) && !item.tags.contains($0)
                    }
                    guard let first = suggestions.first else { return }
                    store.addTag(first, to: item)
                    tagInputText = ""
                    showTagInput = false
                } else if searchText.hasPrefix("#") {
                    let tagQuery = String(searchText.dropFirst()).lowercased()
                    let suggestions = store.allTags.filter { tagQuery.isEmpty || $0.hasPrefix(tagQuery) }
                    guard let first = suggestions.first else { return }
                    activeTagFilter = first
                    searchText = ""
                    showTagAutocomplete = false
                }
            },
            onBackspace: {
                guard !isEditing else { return false }
                guard isSearchFocused, searchText.isEmpty, activeTagFilter != nil else { return false }
                activeTagFilter = nil
                return true
            }
        ))
    }
    
    private func loadPreviewImage(for item: ClipboardItem) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = store.image(for: item)
                continuation.resume(returning: img)
            }
        }
    }
    
    private func loadInitialChunk(for item: ClipboardItem) async {
        chunkedText.isLoadingMore = true // Initial load spinner
        
        let chunkResult = await Task.detached(priority: .userInitiated) {
            self.store.textChunk(for: item, charCount: ChunkedTextState.initialChars)
        }.value
        
        if let result = chunkResult {
            chunkedText.visibleText = result.text
            chunkedText.totalBytes = result.totalBytes
            chunkedText.loadedCharCount = result.text.count
            chunkedText.reachedEOF = result.reachedEOF
        }
        chunkedText.isLoadingMore = false
    }
    
    private func loadNextChunk(for item: ClipboardItem) async {
        guard !chunkedText.isLoadingMore && chunkedText.hasMore else { return }
        
        chunkedText.isLoadingMore = true
        let nextCharCount = chunkedText.loadedCharCount + ChunkedTextState.chunkSize
        
        let chunkResult = await Task.detached(priority: .userInitiated) {
            self.store.textChunk(for: item, charCount: nextCharCount)
        }.value
        
        if let result = chunkResult {
            chunkedText.visibleText = result.text
            chunkedText.totalBytes = result.totalBytes
            chunkedText.loadedCharCount = result.text.count
            chunkedText.reachedEOF = result.reachedEOF
        }
        chunkedText.isLoadingMore = false
    }
    
    private func formattedByteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formattedSize(bytes: Int) -> String {
        return formattedByteCount(bytes)
    }
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary.opacity(0.7))
                .font(.system(size: 13, weight: .medium))

            if let tag = activeTagFilter {
                HStack(spacing: 3) {
                    Text("#\(tag)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(TagChip.color(for: tag))
                    Button(action: { activeTagFilter = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(TagChip.color(for: tag).opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(TagChip.color(for: tag).opacity(0.12))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(TagChip.color(for: tag).opacity(0.2), lineWidth: 0.5))
            }

            TextField(store.allTags.isEmpty ? "Search clipboard…" : "Search or #tag…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.5))
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Item count
            Text("\(filteredItems.count) items")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color(NSColor.controlBackgroundColor)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.primary.opacity(0.15)),
                    alignment: .bottom
                )
        )
    }
    
    private var listPane: some View {
        Group {
            if filteredItems.isEmpty {
                VStack {
                    Spacer()
                    Text(searchText.isEmpty && activeTagFilter == nil ? "No clipboard history" : "No matches")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ClipboardListView(
                    items: filteredItems,
                    selectedIndex: $selectedIndex,
                    scrollTrigger: $scrollTrigger,
                    store: store,
                    onSelect: onCopyToClipboard,
                    onPaste: onPaste,
                    onDelete: { item in store.delete(item) },
                    onDismiss: onDismiss,
                    selectedID: selectedID,
                    selectedIDs: $selectedIDs,
                    onSelectSingle: selectSingle,
                    onToggleSelection: toggleSelection,
                    onExtendSelectionTo: extendSelectionTo,
                    onTagTap: { tag in activeTagFilter = tag }
                )
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private var detailPane: some View {
        VStack(spacing: 0) {
            // Header with count info or type indicator
            HStack {
                Spacer()
                
                if selectionCount > 1 {
                    // Multi-selection header
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                        Text("\(selectionCount) items selected")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(4)
                } else if let item = selectedItem {
                    // Single selection header
                    if isEditing {
                        HStack(spacing: 6) {
                            Text("Editing")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .cornerRadius(4)
                    } else {
                        HStack(spacing: 6) {
                            Text(item.type == .text ? "Text" : "Image")
                            
                            if item.isFileBacked {
                                Text("Large")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.8))
                                    .cornerRadius(4)
                            }
                            
                            if let size = itemSize, size > 0 {
                                Text(formattedByteCount(size))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                // Action buttons - only show for single selection or hide for multi
                if selectionCount <= 1 {
                    HStack(spacing: 12) {
                        if let item = selectedItem, item.isEditable {
                            Button(action: {
                                if isEditing {
                                    exitEditMode()
                                } else {
                                    enterEditMode()
                                }
                            }) {
                                Image(systemName: "square.and.pencil")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(isEditing ? .blue : .primary)
                            .help(isEditing ? "Stop editing (auto-saved)" : "Edit item")
                        }

                        Button(action: { if let item = selectedItem { onCopyToClipboard(item) } }) {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .help("Copy")
                        
                        if selectedItem?.type == .image && previewImage != nil {
                            Button(action: {
                                if let img = previewImage { PasteController.saveImageToDisk(img) }
                            }) {
                                Image(systemName: "arrow.down.to.line")
                            }
                            .buttonStyle(.plain)
                            .help("Save image")
                        }
                        
                        // OCR button — only for image items without existing OCR text
                        if selectedItem?.type == .image && previewImage != nil && selectedItem?.ocrText == nil {
                            Button(action: {
                                Task {
                                    guard let img = previewImage, let item = selectedItem else { return }
                                    isExtractingText = true
                                    let result = await OCRService.shared.recognizeText(from: img)
                                    let text = result ?? "No text found in this image."
                                    store.setOCRText(text, for: item)
                                    isExtractingText = false
                                }
                            }) {
                                Image(systemName: isExtractingText ? "ellipsis.circle" : "text.viewfinder")
                            }
                            .buttonStyle(.plain)
                            .disabled(isExtractingText)
                            .help("Extract Text from Image")
                        }
                        
                        Button(action: { if let item = selectedItem { store.togglePin(for: item) } }) {
                            Image(systemName: selectedItem?.isPinned == true ? "pin.fill" : "pin")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(selectedItem?.isPinned == true ? .accentColor : .secondary)
                        .help(selectedItem?.isPinned == true ? "Unpin (⌘P)" : "Pin to top (⌘P)")

                        Button(action: { if let item = selectedItem { store.toggleBookmark(for: item) } }) {
                            Image(systemName: selectedItem?.isBookmarked == true ? "bookmark.fill" : "bookmark")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(selectedItem?.isBookmarked == true ? .yellow : .secondary)
                        .help(selectedItem?.isBookmarked == true ? "Remove bookmark (⌘B)" : "Bookmark — protect from deletion (⌘B)")
                        
                        Button(action: { if let item = selectedItem { store.delete(item) } }) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .help("Delete")
                    }
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            
            Divider()
            
            // Content preview
            ScrollView {
                if selectionCount > 1 {
                    // Multi-selection summary
                    multiSelectionSummary
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                } else if let item = selectedItem {
                    itemContent(item)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    Text("Select an item")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Tag section (single selection only)
            if selectionCount <= 1, let item = selectedItem {
                Divider()
                tagSection(for: item)
            }
        }
    }
    
    @ViewBuilder
    private var multiSelectionSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Count breakdown
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Items")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text("\(selectionCount)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Size")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text(formattedByteCount(selectedItemsTotalSize))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Type breakdown
            let textCount = selectedItems.filter { $0.type == .text }.count
            let imageCount = selectedItems.filter { $0.type == .image }.count
            
            VStack(alignment: .leading, spacing: 8) {
                if textCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.secondary)
                        Text("\(textCount) text \(textCount == 1 ? "item" : "items")")
                            .font(.system(size: 12))
                    }
                }
                
                if imageCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                        Text("\(imageCount) image \(imageCount == 1 ? "item" : "items")")
                            .font(.system(size: 12))
                    }
                }
            }
            
            Divider()
            
            // Download All Images button (only show if all selected items are images)
            if textCount == 0 && imageCount > 0 {
                Button(action: downloadAllImages) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.to.line")
                        Text("Download All (\(imageCount))")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Divider()
            }
            
            // First selected item preview (optional)
            if let firstItem = selectedItems.first, firstItem.type == .text {
                VStack(alignment: .leading, spacing: 6) {
                    Text("First item preview")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                    
                    let preview = (firstItem.textContent ?? "").prefix(200)
                    Text(String(preview))
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(4)
                        .truncationMode(.tail)
                }
            }
            
            Divider()
            
            if showDeleteConfirmation {
                // Inline confirmation — avoids NSPanel key-resign issue with .alert
                VStack(spacing: 8) {
                    Text("Delete \(selectionCount) items permanently?")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary.opacity(0.85))
                    
                    HStack(spacing: 10) {
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.15)) {
                                showDeleteConfirmation = false
                            }
                        }) {
                            Text("Cancel")
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.primary)
                        
                        Button(action: {
                            store.delete(selectedItems)
                            showDeleteConfirmation = false
                        }) {
                            Text("Delete")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.red.opacity(0.85))
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                    }
                }
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showDeleteConfirmation = true
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Delete \(selectionCount) Items...")
                    }
                    .foregroundColor(isDeleteHovered ? .red : .secondary.opacity(0.7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .onHover { hovering in
                    isDeleteHovered = hovering
                }
                .transition(.opacity)
            }
        }
    }
    
    @ViewBuilder
    private func itemContent(_ item: ClipboardItem) -> some View {
        switch item.type {
        case .text:
            if item.isTruncated {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.textContent ?? "")
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    
                    Label("Content was too large to store (\(formattedSize(bytes: item.originalSizeBytes ?? 0))). Showing first 500 characters.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            } else if item.isFileBacked || (item.textContent?.count ?? 0) > 5000 {
                textContent(item)
            } else if isEditing {
                TextEditor(text: $editText)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 200, maxHeight: .infinity)
                    .focused($isTextEditorFocused)
            } else {
                Text(item.textContent ?? "")
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .image:
            VStack(spacing: 12) {
                if let img = previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                } else {
                    // Loading placeholder
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: 200)
                }
                
                // OCR result
                if isExtractingText {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 12)
                } else if let ocrText = item.ocrText {
                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(height: 0.5)
                        
                        HStack(alignment: .top) {
                            Text(ocrText)
                                .font(.system(size: 13))
                                .textSelection(.enabled)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            
                            Button(action: {
                                NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(ocrText, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .help("Copy extracted text")
                        }
                        .padding(.top, 12)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func textContent(_ item: ClipboardItem) -> some View {
        LazyVStack(spacing: 8, pinnedViews: []) {
            Text(chunkedText.visibleText)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            
            if chunkedText.isLoadingMore {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 8)
            } else if chunkedText.hasMore {
                // This hint fires .onAppear only when it scrolls into view (LazyVStack)
                // That's what triggers the next chunk load
                Text("— \(formattedByteCount(chunkedText.totalBytes)) total · scroll to load more —")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                    .onAppear {
                        Task { await loadNextChunk(for: item) }
                    }
            }
        }
    }
    
    private func enterEditMode() {
        guard let item = selectedItem, item.isEditable else { return }
        editingItemID = item.id
        editText = item.textContent ?? ""
        isEditing = true
        DispatchQueue.main.async {
            isTextEditorFocused = true
        }
    }
    
    private func exitEditMode() {
        // Commit edit to the original item (not selectedItem, which may have changed)
        if let itemID = editingItemID,
           let item = store.items.first(where: { $0.id == itemID }) {
            store.updateText(editText, for: item)
            
            NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(editText, forType: .string)
        }
        editingItemID = nil
        isEditing = false
        isTextEditorFocused = false
    }

    private func navigateUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
            // Clear multi-selection when navigating without Shift
            if let item = filteredItems[safe: selectedIndex] {
                selectedID = item.id
                selectedIDs = [item.id]
                selectionAnchor = item.id
            }
        }
    }
    
    private func navigateDown() {
        if selectedIndex < filteredItems.count - 1 {
            selectedIndex += 1
            // Clear multi-selection when navigating without Shift
            if let item = filteredItems[safe: selectedIndex] {
                selectedID = item.id
                selectedIDs = [item.id]
                selectionAnchor = item.id
            }
            // selectedID will be synced via onChange(of: selectedIndex)
        }
    }
    
    private var actionBar: some View {
        HStack(spacing: 16) {
            // Navigate buttons - minimal, elegant
            HStack(spacing: 6) {
                Button(action: navigateDown) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                
                Button(action: navigateUp) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
            
            Text("Navigate")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary.opacity(0.8))

            Color.primary.opacity(0.1)
                .frame(width: 2, height: 14)

            HStack(spacing: 4) {
                Text("⌘↑↓")
                    .font(.system(size: 10))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                Text("multi-select")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            HStack(spacing: 4) {
                Text("⌘P")
                    .font(.system(size: 10))
                Text("pin")
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary.opacity(0.6))
            .padding(.leading, 8)

            HStack(spacing: 4) {
                Text("⌘B")
                    .font(.system(size: 10))
                Text("save")
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary.opacity(0.6))
            .padding(.leading, 4)
            
            if selectedItem?.type == .image {
                HStack(spacing: 4) {
                    Text("⌘S")
                        .font(.system(size: 10))
                    Text("save")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.leading, 4)
            }
            
            Spacer()
            
            // Keyboard shortcut hint
            HStack(spacing: 4) {
                Image(systemName: "return")
                    .font(.system(size: 10))
                Text("to paste")
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary.opacity(0.6))
            
            // Paste button - Apple-style, refined
            Button(action: { if let item = selectedItem { onPaste(item) } }) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .medium))
                    Text("Paste")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.85))
                )
                .foregroundColor(Color(NSColor.windowBackgroundColor))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color(NSColor.controlBackgroundColor)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.primary.opacity(0.15)),
                    alignment: .top
                )
        )
    }

    // MARK: - Tag views

    private var tagAutocompleteBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tagSuggestions, id: \.self) { tag in
                    Button(action: {
                        activeTagFilter = tag
                        searchText = ""
                        showTagAutocomplete = false
                    }) {
                        Text("#\(tag)")
                            .font(.system(size: 11))
                            .foregroundColor(TagChip.color(for: tag))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(TagChip.color(for: tag).opacity(0.10))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func tagSection(for item: ClipboardItem) -> some View {
        let inputSuggestions = showTagInput ? tagInputSuggestions(excluding: item.tags) : []
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(item.tags, id: \.self) { tag in
                        TagChip(label: tag, onRemove: {
                            store.removeTag(tag, from: item)
                        })
                    }
                    if showTagInput {
                        HStack(spacing: 6) {
                            TextField("tag name", text: $tagInputText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .focused($isTagInputFocused)
                                .frame(minWidth: 60)
                            Button("Cancel") {
                                tagInputText = ""
                                showTagInput = false
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: { showTagInput = true }) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Add tag")
                                    .font(.system(size: 11))
                                Text("⌘T")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.3))
                            }
                            .foregroundColor(.secondary.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !inputSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(inputSuggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                store.addTag(suggestion, to: item)
                                tagInputText = ""
                                showTagInput = false
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundColor(TagChip.color(for: suggestion))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(TagChip.color(for: suggestion).opacity(0.10))
                            .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Monitors global key events for the window
struct GlobalKeyMonitor: NSViewRepresentable {
    let isEditing: Bool
    let onUp: () -> Void
    let onDown: () -> Void
    let onExtendUp: () -> Void
    let onExtendDown: () -> Void
    let onEnter: () -> Void
    let onEscape: () -> Void
    let onDelete: () -> Void
    let onCopy: () -> Void
    let onPin: () -> Void
    let onBookmark: () -> Void
    let onSaveImage: () -> Void
    let onAddTag: () -> Void
    let onTabComplete: () -> Void
    let onBackspace: () -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            // Add local monitor to window
            guard let window = view.window else { return }
            
            let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let isEditing = context.coordinator.isEditing
                switch event.keyCode {
                case 126: // Up
                    if isEditing { return event }
                    if event.modifierFlags.contains(.shift) {
                        context.coordinator.onExtendUp?()
                    } else {
                        context.coordinator.onUp?()
                    }
                    return nil // Consume event
                case 125: // Down
                    if isEditing { return event }
                    if event.modifierFlags.contains(.shift) {
                        context.coordinator.onExtendDown?()
                    } else {
                        context.coordinator.onDown?()
                    }
                    return nil // Consume event
                case 36: // Enter
                    if isEditing { return event }
                    context.coordinator.onEnter?()
                    return nil
                case 53: // Escape
                    context.coordinator.onEscape?()
                    return nil
                case 51: // Delete/Backspace
                    if isEditing {
                        if event.modifierFlags.contains(.command) {
                            return nil // ⌘Delete is no-op
                        }
                        return event
                    }
                    if event.modifierFlags.contains(.command) {
                        context.coordinator.onDelete?()
                        return nil
                    }
                    if context.coordinator.onBackspace?() == true { return nil }
                    return event
                case 8: // C (for Copy)
                    if event.modifierFlags.contains(.command) {
                        if isEditing { return event }
                        // If text is selected in a text view, let the system handle native copy
                        if let responder = view.window?.firstResponder, responder is NSTextView {
                            return event
                        }
                        context.coordinator.onCopy?()
                        return nil
                    }
                    return event
                case 35: // Cmd+P (P is 35)
                    if event.modifierFlags.contains(.command) {
                        if isEditing { return nil }
                        context.coordinator.onPin?()
                        return nil
                    }
                    return event
                case 11: // Cmd+B (B is 11)
                    if event.modifierFlags.contains(.command) {
                        if isEditing { return nil }
                        context.coordinator.onBookmark?()
                        return nil
                    }
                    return event
                case 1: // Cmd+S (S is 1)
                    if event.modifierFlags.contains(.command) {
                        if isEditing { return event }
                        context.coordinator.onSaveImage?()
                        return nil
                    }
                    return event
                case 17: // Cmd+T (T is 17)
                    if event.modifierFlags.contains(.command) {
                        if isEditing { return nil }
                        context.coordinator.onAddTag?()
                        return nil
                    }
                    return event
                case 48: // Tab
                    if isEditing { return event }
                    context.coordinator.onTabComplete?()
                    return nil
                default:
                    return event
                }
            }
            
            context.coordinator.monitor = monitor
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEditing = isEditing
        context.coordinator.onUp = onUp
        context.coordinator.onDown = onDown
        context.coordinator.onExtendUp = onExtendUp
        context.coordinator.onExtendDown = onExtendDown
        context.coordinator.onEnter = onEnter
        context.coordinator.onEscape = onEscape
        context.coordinator.onDelete = onDelete
        context.coordinator.onCopy = onCopy
        context.coordinator.onPin = onPin
        context.coordinator.onBookmark = onBookmark
        context.coordinator.onSaveImage = onSaveImage
        context.coordinator.onAddTag = onAddTag
        context.coordinator.onTabComplete = onTabComplete
        context.coordinator.onBackspace = onBackspace
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var monitor: Any?
        var isEditing: Bool = false
        var onUp: (() -> Void)?
        var onDown: (() -> Void)?
        var onExtendUp: (() -> Void)?
        var onExtendDown: (() -> Void)?
        var onEnter: (() -> Void)?
        var onEscape: (() -> Void)?
        var onDelete: (() -> Void)?
        var onCopy: (() -> Void)?
        var onPin: (() -> Void)?
        var onBookmark: (() -> Void)?
        var onSaveImage: (() -> Void)?
        var onAddTag: (() -> Void)?
        var onTabComplete: (() -> Void)?
        var onBackspace: (() -> Bool)?
        
        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
