import SwiftUI
import AppKit

/// A simple wrapper that detects clicks with modifier keys
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

