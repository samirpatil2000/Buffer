import SwiftUI
import AppKit

/// Vertical list of clipboard items with keyboard navigation
struct ClipboardListView: View {
    let items: [ClipboardItem]
    @Binding var selectedIndex: Int
    let store: ClipboardStore
    let onSelect: (ClipboardItem) -> Void
    let onPaste: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipboardItemRow(
                            item: item,
                            store: store,
                            isSelected: index == selectedIndex
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedIndex = index
                            onSelect(item)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .onChange(of: selectedIndex) { newValue in
                if let item = items[safe: newValue] {
                    proxy.scrollTo(item.id, anchor: .center)
                }
            }
        }
        .background(KeyboardHandler(
            onUp: { if selectedIndex > 0 { selectedIndex -= 1 } },
            onDown: { if selectedIndex < items.count - 1 { selectedIndex += 1 } },
            onEnter: { if let item = items[safe: selectedIndex] { onPaste(item) } },
            onCopy: { if let item = items[safe: selectedIndex] { onSelect(item) } },
            onDelete: {
                if let item = items[safe: selectedIndex] {
                    onDelete(item)
                    if selectedIndex >= items.count - 1 && selectedIndex > 0 {
                        selectedIndex -= 1
                    }
                }
            },
            onEscape: onDismiss
        ))
    }
}

struct KeyboardHandler: NSViewRepresentable {
    let onUp: () -> Void
    let onDown: () -> Void
    let onEnter: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onEscape: () -> Void
    
    func makeNSView(context: Context) -> KeyboardView {
        let view = KeyboardView()
        view.onUp = onUp
        view.onDown = onDown
        view.onEnter = onEnter
        view.onCopy = onCopy
        view.onDelete = onDelete
        view.onEscape = onEscape
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }
    
    func updateNSView(_ nsView: KeyboardView, context: Context) {
        nsView.onUp = onUp
        nsView.onDown = onDown
        nsView.onEnter = onEnter
        nsView.onCopy = onCopy
        nsView.onDelete = onDelete
        nsView.onEscape = onEscape
    }
}

class KeyboardView: NSView {
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onEnter: (() -> Void)?
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?
    var onEscape: (() -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: onUp?()
        case 125: onDown?()
        case 36: onEnter?()
        case 53: onEscape?()
        case 51: onDelete?()
        case 8 where event.modifierFlags.contains(.command): onCopy?()
        default: super.keyDown(with: event)
        }
    }
}
