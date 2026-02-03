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
    }
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
            
            TextField("Type to search...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Sort buttons (visual only for now)
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                Image(systemName: "command")
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
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
            if let img = store.image(for: item) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Image not found")
                    .foregroundColor(.secondary)
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
        HStack {
            // Navigate buttons
            HStack(spacing: 8) {
                Button(action: navigateDown) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                Button(action: navigateUp) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .foregroundColor(.primary)
            
            Text("Navigate")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Paste button - Green color
            Button(action: { if let item = selectedItem { onPaste(item) } }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.left")
                    Text("Paste")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
