import Cocoa

/// Handles pasting content into the frontmost application
class PasteController {
    
    /// Copy item content back to system clipboard
    static func copyToClipboard(_ item: ClipboardItem, store: ClipboardStore) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            // Use full text from file if file-backed, otherwise use inline content
            if let text = store.fullText(for: item) {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let image = store.image(for: item),
               let tiffData = image.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
            }
        }
    }
    
    /// Paste item into the frontmost application, restoring focus to the previously active app.
    ///
    /// - Parameters:
    ///   - item: The clipboard item whose content should be pasted.
    ///   - store: The clipboard store used to retrieve the full item content.
    ///   - previousApp: The application that was frontmost before Buffer's window was shown.
    ///     When provided, focus is returned to this app before the simulated ⌘V keystroke
    ///     so the paste lands in the correct window.
    static func paste(_ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication? = nil) {
        // First copy to clipboard
        copyToClipboard(item, store: store)
        
        if let app = previousApp {
            // Re-activate the previously focused app so the simulated ⌘V targets it
            app.activate(options: .activateIgnoringOtherApps)
            
            // Allow enough time for the app to regain focus before sending the keystroke
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                simulatePaste()
            }
        } else {
            // Fallback: small delay to ensure clipboard is updated
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                simulatePaste()
            }
        }
    }
    
    /// Simulate Command + V keystroke
    private static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key code for 'V' is 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        
        // Add Command modifier
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        
        // Post the events
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
