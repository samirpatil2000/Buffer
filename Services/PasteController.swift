import Cocoa
import UniformTypeIdentifiers
import ApplicationServices

/// The decision the paste path should take based on current Accessibility trust state.
/// Pure and side-effect free so it can be unit tested without touching the OS.
enum PasteAccessDecision: Equatable {
    /// Trusted: synthesize Cmd+V as usual.
    case proceed
    /// Not trusted: still write the pasteboard, but surface guidance instead of
    /// letting the synthetic keystroke silently fail.
    case showGuidance
}

/// Wraps the macOS Accessibility (AXIsProcessTrusted) permission that the synthetic
/// Cmd+V paste keystroke requires. Keeps the raw API calls in one small place and
/// never persists state, the OS owns the truth.
enum AccessibilityManager {

    /// Non-prompting status read. Never shows the system dialog.
    /// Use this for status checks (launch, Settings row, paste decision).
    static func isTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Prompting check. Shows the system "Open System Settings" dialog when the
    /// process is not yet trusted. Call this ONLY in response to an explicit user
    /// action (for example a button), never automatically.
    @discardableResult
    static func requestAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open the Accessibility pane in System Settings so the user can grant access.
    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Pure mapping from trust state to the paste-path decision. Unit tested.
    static func pasteDecision(isTrusted: Bool) -> PasteAccessDecision {
        return isTrusted ? .proceed : .showGuidance
    }

    /// Show a modal alert guiding the user to grant Accessibility, modeled on
    /// UpdateService.showUpdateAlert. The pasteboard has already been written by
    /// the caller, so the user can still paste manually with Cmd+V.
    static func showPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Buffer needs Accessibility access to paste"
        alert.informativeText = "Your content was copied to the clipboard, so you can paste it manually with Cmd+V. To let Buffer paste automatically, grant Accessibility access in System Settings."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
}

/// Handles pasting content into the frontmost application
class PasteController {
    
    /// Get or create temp directory for paste operations
    private static func getTempDirectory() -> URL? {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BufferPaste")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    /// Save image with proper filename and return file URL
    private static func saveImageToTemp(_ image: NSImage, fileName: String) -> URL? {
        guard let tempDir = getTempDirectory() else { return nil }
        
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        if let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
            return fileURL
        }
        return nil
    }
    
    /// Write a text item's representations as a single pasteboard item (richest flavour first).
    /// Caller must have called `clearContents()` - `writeObjects` appends to the current owner.
    /// .rtfd is written first (resolution 2 fallback): pasting via .rtf alone does not preserve
    /// inline images, empirically verified - see feature3-design.md section 4.8.
    private static func writeTextPayload(_ item: ClipboardItem, store: ClipboardStore, to pasteboard: NSPasteboard) {
        guard let text = store.fullText(for: item) else { return }
        let pbItem = NSPasteboardItem()
        if let rtfd = item.rtfdData { pbItem.setData(rtfd, forType: .rtfd) }
        if let rtf = item.rtfData { pbItem.setData(rtf, forType: .rtf) }
        if let html = item.htmlData { pbItem.setData(html, forType: .html) }
        pbItem.setString(text, forType: .string)
        pasteboard.writeObjects([pbItem])
    }

    /// Copy item content back to system clipboard
    static func copyToClipboard(_ item: ClipboardItem, store: ClipboardStore) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            writeTextPayload(item, store: store, to: pasteboard)
        case .image:
            if let image = store.image(for: item),
               let tiffData = image.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
            }
        }
    }
    
    /// Copy multiple items content back to system clipboard
    static func copyMultipleToClipboard(_ items: [ClipboardItem], store: ClipboardStore) {
        guard !items.isEmpty else { return }
        if items.count == 1, let first = items.first {
            copyToClipboard(first, store: store)
            return
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        let textItems = items.filter { $0.type == .text }
        let imageItems = items.filter { $0.type == .image }
        
        if !textItems.isEmpty {
            let joinedText = textItems.compactMap { store.fullText(for: $0) }.joined(separator: "\n")
            pasteboard.setString(joinedText, forType: .string)
        } else if !imageItems.isEmpty {
            var imageURLs: [URL] = []
            for (index, imageItem) in imageItems.enumerated() {
                if let image = store.image(for: imageItem) {
                    let paddedNumber = String(format: "%04d", index + 1)
                    let fileName = "image-\(paddedNumber).png"
                    if let fileURL = saveImageToTemp(image, fileName: fileName) {
                        imageURLs.append(fileURL)
                    }
                }
            }
            if !imageURLs.isEmpty {
                pasteboard.writeObjects(imageURLs as [NSPasteboardWriting])
            }
        }
    }
    
    /// Paste item into the frontmost application
    static func paste(_ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication? = nil) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            writeTextPayload(item, store: store, to: pasteboard)
        case .image:
            if let image = store.image(for: item) {
                // Save image to temp with proper name
                if let fileURL = saveImageToTemp(image, fileName: "image-0001.png") {
                    pasteboard.writeObjects([fileURL as NSPasteboardWriting])
                } else {
                    // Fallback to TIFF if file save fails
                    if let tiffData = image.tiffRepresentation {
                        pasteboard.setData(tiffData, forType: .tiff)
                    }
                }
            }
        }

        // Pasteboard is written above, so the user can paste manually even without
        // Accessibility. Only synthesize Cmd+V when trusted, otherwise guide the user.
        if AccessibilityManager.pasteDecision(isTrusted: AccessibilityManager.isTrusted()) == .showGuidance {
            AccessibilityManager.showPermissionAlert()
            return
        }

        // Reactivate previous app, then simulate paste after it has focus
        previousApp?.activate(options: .activateIgnoringOtherApps)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Post ignore notification right before paste
            NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
            simulatePaste()
        }
    }
    
    /// Paste multiple items into the frontmost application
    /// Text items are joined with newlines, images are handled individually
    static func pasteMultiple(_ items: [ClipboardItem], store: ClipboardStore, previousApp: NSRunningApplication? = nil) {
        guard !items.isEmpty else { return }
        if items.count == 1, let first = items.first, first.type == .text {
            paste(first, store: store, previousApp: previousApp)
            return
        }

        // Without Accessibility the synthetic Cmd+V is silently dropped, and the
        // multi-step paste below would also leave images only partially placed.
        // Write a best-effort pasteboard representation so manual Cmd+V works, then
        // guide the user instead of synthesizing keystrokes that cannot land.
        if AccessibilityManager.pasteDecision(isTrusted: AccessibilityManager.isTrusted()) == .showGuidance {
            copyMultipleToClipboard(items, store: store)
            AccessibilityManager.showPermissionAlert()
            return
        }

        let pasteboard = NSPasteboard.general
        
        // Separate items by type
        let textItems = items.filter { $0.type == .text }
        let hasImages = items.contains { $0.hasImages }      // replaces the imageItems binding
        
        // If we have text items, paste them first
        if !textItems.isEmpty {
            pasteboard.clearContents()
            let joinedText = textItems.compactMap { store.fullText(for: $0) }.joined(separator: "\n")
            pasteboard.setString(joinedText, forType: .string)
            
            // If all items are text, paste once and done
            if !hasImages {
                previousApp?.activate(options: .activateIgnoringOtherApps)
                simulatePasteWithCustomDelay(0.1)
                return
            }
            
            // Paste text first, then images together after
            previousApp?.activate(options: .activateIgnoringOtherApps)
            simulatePasteWithCustomDelay(0.1)
            
            // Then paste all images together
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                
                // Save all images (pure images and combined-item attachments alike) and collect URLs
                var imageURLs: [URL] = []
                let images = items.flatMap { store.allImages(for: $0) }
                for (index, image) in images.enumerated() {
                    let fileName = "image-\(String(format: "%04d", index + 1)).png"
                    if let fileURL = saveImageToTemp(image, fileName: fileName) {
                        imageURLs.append(fileURL)
                    }
                }
                
                // Paste all URLs together
                if !imageURLs.isEmpty {
                    pasteboard.writeObjects(imageURLs as [NSPasteboardWriting])
                    simulatePasteWithCustomDelay(0.05)
                }
            }
        } else if hasImages {
            // Images only - paste all together at once (like Finder multi-select)
            previousApp?.activate(options: .activateIgnoringOtherApps)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                pasteboard.clearContents()
                
                // Save all images and collect URLs
                var imageURLs: [URL] = []
                let images = items.flatMap { store.allImages(for: $0) }
                for (index, image) in images.enumerated() {
                    let fileName = "image-\(String(format: "%04d", index + 1)).png"
                    if let fileURL = saveImageToTemp(image, fileName: fileName) {
                        imageURLs.append(fileURL)
                    }
                }
                
                // Paste all URLs together at once
                if !imageURLs.isEmpty {
                    pasteboard.writeObjects(imageURLs as [NSPasteboardWriting])
                    simulatePasteWithCustomDelay(0.05)
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
    
    /// Simulate Command + V keystroke with delay to ensure pasteboard is ready
    private static func simulatePasteWithDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Post ignore notification right before paste
            NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
            simulatePaste()
        }
    }
    
    /// Simulate Command + V keystroke with custom delay
    private static func simulatePasteWithCustomDelay(_ delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Post ignore notification right before paste
            NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
            simulatePaste()
        }
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
    
    /// Save a text snippet to disk using NSSavePanel with intelligent syntax detection
    static func saveTextToDisk(_ text: String, suggestedFileName: String? = nil) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            
            let detection = SyntaxDetector.detect(text: text)
            var allowedTypes: [UTType] = [detection.contentType]
            if !allowedTypes.contains(.plainText) {
                allowedTypes.append(.plainText)
            }
            if !allowedTypes.contains(.utf8PlainText) {
                allowedTypes.append(.utf8PlainText)
            }
            panel.allowedContentTypes = allowedTypes
            panel.allowsOtherFileTypes = true
            panel.canCreateDirectories = true
            
            panel.nameFieldStringValue = suggestedFileName ?? detection.suggestedFileName
            
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    print("[Buffer] Saved text snippet to \(url.lastPathComponent)")
                } catch {
                    print("[Buffer] Failed to save text to disk: \(error)")
                }
            }
        }
    }
}

