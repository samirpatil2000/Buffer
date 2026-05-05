import SwiftUI
import AppKit

/// Vertical list of clipboard items with keyboard navigation
struct ClipboardListView: View {
    let items: [ClipboardItem]
    @Binding var selectedIndex: Int
    @Binding var scrollTrigger: Bool
    let store: ClipboardStore
    let showsQuickPasteNumbers: Bool
    let onSelect: (ClipboardItem) -> Void
    let onPaste: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void
    let onDismiss: () -> Void
    
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
                            isMultiSelected: selectedIDs.contains(item.id),
                            joinsSelectionAbove: index > 0 && selectedIDs.contains(items[index - 1].id),
                            joinsSelectionBelow: index < items.count - 1 && selectedIDs.contains(items[index + 1].id),
                            quickPasteNumber: showsQuickPasteNumbers && index < 5 ? index + 1 : nil
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
                .padding(4)
            }
            .background(
                ScrollViewConfigurator { scrollView in
                    scrollView.scrollerStyle = .overlay
                    scrollView.verticalScroller?.controlSize = .small
                }
            )
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

private struct ScrollViewConfigurator: NSViewRepresentable {
    let configure: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ConfiguratorView()
        view.configure = configure
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? ConfiguratorView {
            view.configure = configure
            view.applyConfigurationIfNeeded()
        }
    }

    private final class ConfiguratorView: NSView {
        var configure: ((NSScrollView) -> Void)?
        private weak var configuredScrollView: NSScrollView?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            applyConfigurationIfNeeded()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyConfigurationIfNeeded()
        }

        func applyConfigurationIfNeeded() {
            guard let scrollView = enclosingScrollView else { return }
            configure?(scrollView)
            configuredScrollView = scrollView
        }
    }
}
