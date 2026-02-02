import SwiftUI
import AppKit

/// Vertical list of clipboard items with keyboard navigation
struct ClipboardListView: View {
    let items: [ClipboardItem]
    @Binding var selectedIndex: Int
    let store: ClipboardStore
    let onSelect: (ClipboardItem) -> Void  // Single click - copy to clipboard
    let onPaste: (ClipboardItem) -> Void   // Enter key - paste
    let onDelete: (ClipboardItem) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipboardItemRow(
                            item: item,
                            store: store,
                            isSelected: index == selectedIndex
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        // Single gesture - no delay
                        .gesture(
                            TapGesture()
                                .onEnded {
                                    selectedIndex = index
                                    onSelect(item)
                                }
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { newValue in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(items[safe: newValue]?.id, anchor: .center)
                }
            }
        }
        .background(KeyboardHandler(
            onUp: {
                if selectedIndex > 0 {
                    selectedIndex -= 1
                }
            },
            onDown: {
                if selectedIndex < items.count - 1 {
                    selectedIndex += 1
                }
            },
            onEnter: {
                if let item = items[safe: selectedIndex] {
                    onPaste(item)
                }
            },
            onCopy: {
                if let item = items[safe: selectedIndex] {
                    onSelect(item)
                }
            },
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

// Safe array access
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

/// Handles keyboard input for the list
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
        
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        
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
        case 126: // Up arrow
            onUp?()
        case 125: // Down arrow
            onDown?()
        case 36: // Return/Enter
            onEnter?()
        case 53: // Escape
            onEscape?()
        case 51: // Delete/Backspace
            onDelete?()
        case 8: // C key
            if event.modifierFlags.contains(.command) {
                onCopy?()
            } else {
                super.keyDown(with: event)
            }
        default:
            super.keyDown(with: event)
        }
    }
}
