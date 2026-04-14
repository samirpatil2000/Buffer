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
            onCopyToClipboard: { [weak self] item in
                self?.copyToClipboard(item)
            },
            onPaste: { [weak self] item in
                self?.pasteItem(item)
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
    
    override func showWindow(_ sender: Any?) {
        previousApp = NSWorkspace.shared.frontmostApplication
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
    let onCopyToClipboard: (ClipboardItem) -> Void
    let onPaste: (ClipboardItem) -> Void
    let onDismiss: () -> Void
    
    @FocusState private var isSearchFocused: Bool
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var previewImage: NSImage?
    @State private var chunkedText = ChunkedTextState()
    @State private var scrollTrigger = false  // Triggers scroll on keyboard navigation
    @State private var itemSize: Int?         // Holds computed size of item
    
    
    // OCR state
    @State private var isExtractingText = false
    
    // Track selection by ID so it survives list insertions
    @State private var selectedID: UUID?
    
    private var filteredItems: [ClipboardItem] {
        let baseItems: [ClipboardItem]
        if searchText.isEmpty {
            baseItems = store.items
        } else {
            baseItems = store.items.filter { item in
                guard item.type == .text else { return false }
                return item.textContent?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
        return baseItems.sorted { $0.isPinned && !$1.isPinned }
    }
    
    /// Get the first unpinned item, or the first pinned item if no unpinned items exist
    private var defaultSelectedItem: ClipboardItem? {
        return filteredItems.first(where: { !$0.isPinned }) ?? filteredItems.first
    }
    
    private var selectedItem: ClipboardItem? {
        // Prefer ID-based lookup for stability during list mutations
        if let id = selectedID, let item = filteredItems.first(where: { $0.id == id }) {
            return item
        }
        return filteredItems[safe: selectedIndex]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
            
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
        .onChange(of: searchText) { _ in
            // Find first unpinned item in filtered results
            let defaultItem = defaultSelectedItem
            selectedID = defaultItem?.id
            // Calculate the correct index
            if let index = filteredItems.firstIndex(where: { $0.id == defaultItem?.id }) {
                selectedIndex = index
            } else {
                selectedIndex = 0
            }
        }
        .onChange(of: selectedIndex) { newIndex in
            selectedID = filteredItems[safe: newIndex]?.id
        }
        .onChange(of: store.items) { _ in
            // Preserve selection when items change (new entry added at top)
            guard let id = selectedID else { return }
            if let newIndex = filteredItems.firstIndex(where: { $0.id == id }), selectedIndex != newIndex {
                selectedIndex = newIndex
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bufferWindowDidOpen)) { _ in
            searchText = ""
            // Select first unpinned item, or first item if all are pinned
            let firstUnpinned = store.items.first(where: { !$0.isPinned }) ?? store.items.first
            selectedID = firstUnpinned?.id
            // Find the correct index in the filtered (sorted) items
            if let index = filteredItems.firstIndex(where: { $0.id == firstUnpinned?.id }) {
                selectedIndex = index
            } else {
                selectedIndex = 0
            }
            // Delay needed for NSHostingView to have settled as key window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .task(id: selectedItem?.id) {
            // Clear preview
            previewImage = nil
            chunkedText = ChunkedTextState()
            isExtractingText = false
            itemSize = nil
            
            // Load new preview async
            if let item = selectedItem {
                itemSize = store.itemSize(for: item)
                
                if item.type == .image {
                    previewImage = await loadPreviewImage(for: item)
                } else if item.type == .text {
                    if item.isFileBacked {
                        await loadInitialChunk(for: item)
                    } else {
                        chunkedText.visibleText = item.textContent ?? ""
                        chunkedText.reachedEOF = true
                    }
                }
            }
        }
        .background(GlobalKeyMonitor(
            onUp: {
                scrollTrigger = true
                navigateUp()
            },
            onDown: {
                scrollTrigger = true
                navigateDown()
            },
            onEnter: { if let item = selectedItem { onPaste(item) } },
            onEscape: onDismiss,
            onDelete: {
                if let item = selectedItem {
                    store.delete(item)
                    // Clear search or reset selection if needed, but the array update will re-render
                }
            },
            onCopy: { if let item = selectedItem { onCopyToClipboard(item) } },
            onBookmark: {
                if let item = selectedItem {
                    store.toggleBookmark(for: item)
                }
            },
            onPin: {
                if let item = selectedItem {
                    store.togglePin(for: item)
                }
            },
            onSaveImage: {
                if selectedItem?.type == .image, let img = previewImage {
                    PasteController.saveImageToDisk(img)
                }
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
            
            TextField("Search clipboard...", text: $searchText)
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
                        .foregroundColor(Color.primary.opacity(0.06)),
                    alignment: .bottom
                )
        )
    }
    
    private var listPane: some View {
        Group {
            if filteredItems.isEmpty {
                VStack {
                    Spacer()
                    Text(searchText.isEmpty ? "No clipboard history" : "No matches")
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
                    selectedID: selectedID
                )
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private var detailPane: some View {
        VStack(spacing: 0) {
            // Type indicator
            HStack {
                Spacer()
                
                if let item = selectedItem {
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
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 12) {
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
                    .help(selectedItem?.isPinned == true ? "Unpin" : "Pin")
                    
                    Button(action: { if let item = selectedItem { store.toggleBookmark(for: item) } }) {
                        Image(systemName: selectedItem?.isBookmarked == true ? "star.fill" : "star")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(selectedItem?.isBookmarked == true ? .yellow : .secondary)
                    .help(selectedItem?.isBookmarked == true ? "Remove Bookmark" : "Bookmark")
                    
                    Button(action: { if let item = selectedItem { store.delete(item) } }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
                .foregroundColor(.secondary)
                .font(.system(size: 13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            
            Divider()
            
            // Content preview
            ScrollView {
                if let item = selectedItem {
                    itemContent(item)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    Text("Select an item")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
            } else if item.isFileBacked {
                textContent(item)
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
                            .fill(Color.primary.opacity(0.06))
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
    
    private func navigateUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }
    
    private func navigateDown() {
        if selectedIndex < filteredItems.count - 1 {
            selectedIndex += 1
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
            
            HStack(spacing: 4) {
                Text("⌘P")
                    .font(.system(size: 10))
                Text("pin")
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary.opacity(0.6))
            .padding(.leading, 8)
            
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
                }
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
                        .foregroundColor(Color.primary.opacity(0.06)),
                    alignment: .top
                )
        )
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Monitors global key events for the window
struct GlobalKeyMonitor: NSViewRepresentable {
    let onUp: () -> Void
    let onDown: () -> Void
    let onEnter: () -> Void
    let onEscape: () -> Void
    let onDelete: () -> Void
    let onCopy: () -> Void
    let onBookmark: () -> Void
    let onPin: () -> Void
    let onSaveImage: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            // Add local monitor to window
            guard let window = view.window else { return }
            
            // We use a property on the window or controller to store the monitor
            // But for simplicity in SwiftUI, we'll use a weak ref approach here
            // or just rely on the view traversing up. 
            // Actually, best way is to add monitor to the window.
            
            let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 126: // Up
                    onUp()
                    return nil // Consume event
                case 125: // Down
                    onDown()
                    return nil // Consume event
                case 36: // Enter
                    onEnter()
                    return nil
                case 53: // Escape
                    onEscape()
                    return nil
                case 51: // Delete
                    // Check if search field is first responder - if so, don't consume delete unless empty?
                    // For now, let's assume Cmd+Delete or just Delete on list.
                    // If we consume Delete always, we can't delete text in search.
                    // So let's only consume if we are NOT editing text OR if modifier is used.
                    // But simpler: Only trigger if search text is empty? 
                    // Let's rely on Command+Delete for item deletion to be safe/standard
                    if event.modifierFlags.contains(.command) {
                        onDelete()
                        return nil
                    }
                    return event
                case 8: // C (for Copy)
                    if event.modifierFlags.contains(.command) {
                        // If text is selected in a text view, let the system handle native copy
                        if let responder = view.window?.firstResponder, responder is NSTextView {
                            return event
                        }
                        onCopy()
                        return nil
                    }
                    return event
                case 11: // B (for Bookmark)
                    if event.modifierFlags.contains(.command) {
                        onBookmark()
                        return nil
                    }
                    return event
                case 35: // Cmd+P (P is 35)
                    if event.modifierFlags.contains(.command) {
                        onPin()
                        return nil
                    }
                    return event
                case 1: // Cmd+S (S is 1)
                    if event.modifierFlags.contains(.command) {
                        onSaveImage()
                        return nil
                    }
                    return event
                default:
                    return event
                }
            }
            
            // Store monitor to remove later? 
            // In a real app we need to clean up. For this snippet, 
            // the monitor lasts as long as the window is open.
            // Since the window is closed/released, the monitor should be cleaned up 
            // if we attached it to the window properly or if we remove it on dismantle.
            // However, NSEvent.addLocalMonitorForEvents returns an object that must be removed.
            
            context.coordinator.monitor = monitor
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var monitor: Any?
        
        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
