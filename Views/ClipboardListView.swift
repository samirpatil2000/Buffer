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
                                .padding(.horizontal, 16)
                                .padding(.vertical, 2)
                        }
                        
                        ClipboardItemRow(
                            item: item,
                            store: store,
                            isSelected: index == selectedIndex
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture(count: 1)
                                .onEnded { _ in
                                    selectedIndex = index
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
