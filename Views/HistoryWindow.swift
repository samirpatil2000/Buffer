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

/// Manages the floating history window
class HistoryWindowController: NSWindowController {
    private let store: ClipboardStore
    
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
        close()
        NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
        PasteController.paste(item, store: store)
    }
    
    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    static let bufferIgnoreNextChange = Notification.Name("bufferIgnoreNextChange")
}

/// Main content view - Split pane with list and detail
struct HistoryContentView: View {
    @ObservedObject var store: ClipboardStore
    let onCopyToClipboard: (ClipboardItem) -> Void
    let onPaste: (ClipboardItem) -> Void
    let onDismiss: () -> Void
    
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var previewImage: NSImage?
    @State private var scrollTrigger = false  // Triggers scroll on keyboard navigation
    
    private var filteredItems: [ClipboardItem] {
        if searchText.isEmpty {
            return store.items
        }
        return store.items.filter { item in
            guard item.type == .text else { return false }
            return item.textContent?.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }
    
    private var selectedItem: ClipboardItem? {
        filteredItems[safe: selectedIndex]
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
            selectedIndex = 0
        }
        .onChange(of: selectedIndex) { _ in
            // Clear preview image when selection changes
            previewImage = nil
            // Load new preview async
            if let item = filteredItems[safe: selectedIndex], item.type == .image {
                Task {
                    previewImage = await loadPreviewImage(for: item)
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
                }
            },
            onCopy: { if let item = selectedItem { onCopyToClipboard(item) } }
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
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary.opacity(0.7))
                .font(.system(size: 13, weight: .medium))
            
            TextField("Search clipboard...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            
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
                    onDismiss: onDismiss
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
                    Text(item.type == .text ? "Text" : "Image")
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
                    
                    Button(action: {}) {
                        Image(systemName: "star")
                    }
                    .buttonStyle(.plain)
                    .help("Favorite")
                    
                    Button(action: {}) {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(.plain)
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
            Text(item.textContent ?? "")
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        case .image:
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
                        onCopy()
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
