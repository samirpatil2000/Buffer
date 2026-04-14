import Cocoa
import UniformTypeIdentifiers

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
    
    /// Paste item into the frontmost application
    static func paste(_ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication? = nil) {
        // First copy to clipboard
        copyToClipboard(item, store: store)

        // Reactivate previous app, then simulate paste after it has focus
        previousApp?.activate(options: .activateIgnoringOtherApps)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            simulatePaste()
        }
    }
    
    /// Paste multiple items into the frontmost application
    /// Text items are joined with newlines, images are handled individually
    static func pasteMultiple(_ items: [ClipboardItem], store: ClipboardStore, previousApp: NSRunningApplication? = nil) {
        guard !items.isEmpty else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // Separate items by type
        let textItems = items.filter { $0.type == .text }
        let imageItems = items.filter { $0.type == .image }
        
        // Join all text items with newlines
        if !textItems.isEmpty {
            let joinedText = textItems.compactMap { store.fullText(for: $0) }.joined(separator: "\n")
            pasteboard.setString(joinedText, forType: .string)
            
            // If all items are text, paste once and done
            if imageItems.isEmpty {
                previousApp?.activate(options: .activateIgnoringOtherApps)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    simulatePaste()
                }
                return
            }
        }
        
        // If we have mixed items (text + images), paste text first, then images
        if !textItems.isEmpty {
            previousApp?.activate(options: .activateIgnoringOtherApps)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                simulatePaste()
            }
            
            // Then paste each image (with delay between each)
            for (index, imageItem) in imageItems.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(index) * 0.25) {
                    if let image = store.image(for: imageItem), let tiffData = image.tiffRepresentation {
                        let imgPasteboard = NSPasteboard.general
                        imgPasteboard.clearContents()
                        imgPasteboard.setData(tiffData, forType: .tiff)
                        simulatePaste()
                    }
                }
            }
        } else if !imageItems.isEmpty {
            // Images only - paste each one
            for (index, imageItem) in imageItems.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 + Double(index) * 0.25) {
                    if let image = store.image(for: imageItem), let tiffData = image.tiffRepresentation {
                        let imgPasteboard = NSPasteboard.general
                        imgPasteboard.clearContents()
                        imgPasteboard.setData(tiffData, forType: .tiff)
                        
                        // Activate app on first image
                        if index == 0 {
                            previousApp?.activate(options: .activateIgnoringOtherApps)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                simulatePaste()
                            }
                        } else {
                            simulatePaste()
                        }
                    }
                }
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
    
    /// Save an image to disk using NSSavePanel
    static func saveImageToDisk(_ image: NSImage) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let timestamp = formatter.string(from: Date())
            
            panel.nameFieldStringValue = "Image-\(timestamp)"
            panel.canCreateDirectories = true
            
            if panel.runModal() == .OK, let url = panel.url {
                guard let tiffData = image.tiffRepresentation,
                      let bitmapRep = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                    print("[Buffer] Failed to create PNG data from image")
                    return
                }
                
                do {
                    try pngData.write(to: url)
                } catch {
                    print("[Buffer] Failed to save image to disk: \(error)")
                }
            }
        }
    }
}
