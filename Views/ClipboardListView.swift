import SwiftUI
import AppKit

/// Vertical list of clipboard items with keyboard navigation
struct ClipboardListView: View {
    let items: [ClipboardItem]
    @Binding var selectedIndex: Int
    @Binding var scrollTrigger: Bool
    let store: ClipboardStore
    let onSelect: (ClipboardItem) -> Void
    let onPaste: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void
    let onDismiss: () -> Void
    let selectedID: UUID?  // Track selection by item ID for stability during list mutations
    
    // Multi-select support
    @Binding var selectedIDs: Set<UUID>
    var onSelectSingle: (UUID) -> Void = { _ in }
    var onToggleSelection: (UUID) -> Void = { _ in }
    var onExtendSelectionTo: (UUID) -> Void = { _ in }
    
    @State private var lastClickedItemID: UUID?
    @State private var lastClickGesture: ClickType = .single
    
    enum ClickType {
        case single
        case shiftClick
        case cmdClick
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    if items.contains(where: { $0.isPinned }) {
                        HStack(spacing: 4) {
                            Image(systemName: "pin")
                            Text("Pinned")
                        }
                        .font(.system(size: 10).smallCaps())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        // Thin separator between pinned and recent items
                        if !item.isPinned && index > 0 && items[index - 1].isPinned {
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 0.5)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                        }
                        
                        ClipboardItemRow(
                            item: item,
                            store: store,
                            isPrimarySelection: item.id == selectedID,
                            isMultiSelected: selectedIDs.contains(item.id)
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        .overlay(
                            ClickModifierDetector { modifiers in
                                selectedIndex = index
                                
                                if modifiers.hasCommand {
                                    // Cmd+click: toggle selection
                                    onToggleSelection(item.id)
                                } else if modifiers.hasShift {
                                    // Shift+click: extend selection
                                    onExtendSelectionTo(item.id)
                                } else {
                                    // Regular click: single select
                                    onSelectSingle(item.id)
                                }
                            },
                            alignment: .center
                        )
                        .simultaneousGesture(
                            TapGesture(count: 1)
                                .onEnded { _ in
                                    // This will be handled by ClickModifierDetector
                                }
                        )
                        .highPriorityGesture(
                            TapGesture(count: 2)
                                .onEnded { _ in
                                    selectedIndex = index
                                    onSelect(item)
                                    onDismiss()
                                }
                        )
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .onChange(of: selectedIndex) { newValue in
                // Only scroll if triggered by keyboard
                if scrollTrigger {
                    if let item = items[safe: newValue] {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            // No anchor means minimal scrolling (just enough to make visible)
                            proxy.scrollTo(item.id)
                        }
                    }
                    scrollTrigger = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .bufferWindowDidOpen)) { _ in
                // Always snap to the top when the window is reopened
                if let firstId = items.first?.id {
                    proxy.scrollTo(firstId, anchor: .top)
                }
            }
        }
    }
}

// MARK: - Click Modifier Detector

/// Detects clicks with modifier keys using NSViewRepresentable
struct ClickModifierDetector: NSViewRepresentable {
    let onClickWithModifiers: (NSEvent.ModifierFlags) -> Void
    
    class ClickView: NSView {
        var onClickWithModifiers: ((NSEvent.ModifierFlags) -> Void)?
        
        override func mouseDown(with event: NSEvent) {
            onClickWithModifiers?(event.modifierFlags)
        }
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = ClickView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.onClickWithModifiers = onClickWithModifiers
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let clickView = nsView as? ClickView {
            clickView.onClickWithModifiers = onClickWithModifiers
        }
    }
}

// MARK: - Modifier Flags Extension

extension NSEvent.ModifierFlags {
    var hasCommand: Bool {
        self.contains(.command)
    }
    
    var hasShift: Bool {
        self.contains(.shift)
    }
}
