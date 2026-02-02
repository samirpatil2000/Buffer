import Foundation
import AppKit
import Combine

/// Monitors the system clipboard for changes and captures new content
class ClipboardWatcher: ObservableObject {
    @Published private(set) var isPaused = false
    
    private let store: ClipboardStore
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var lastContentHash: Int = 0
    private var ignoreNextChange = false
    
    private let pollInterval: TimeInterval = 0.5
    
    init(store: ClipboardStore) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount
        
        // Listen for ignore notification (when copying from history)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleIgnoreNextChange),
            name: .bufferIgnoreNextChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleIgnoreNextChange() {
        ignoreNextChange = true
    }
    
    func startWatching() {
        guard timer == nil else { return }
        
        timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }
    
    func pause() {
        isPaused = true
    }
    
    func resume() {
        isPaused = false
        lastChangeCount = NSPasteboard.general.changeCount
    }
    
    private func checkClipboard() {
        guard !isPaused else { return }
        
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        
        // No change detected
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        
        // Skip if this is a copy from our own history
        if ignoreNextChange {
            ignoreNextChange = false
            return
        }
        
        // Get current frontmost app as source
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        
        // Try to capture text first
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let hash = text.hashValue
            
            // Skip consecutive duplicates
            if hash != lastContentHash {
                lastContentHash = hash
                let item = ClipboardItem.text(text, sourceApp: sourceApp)
                store.add(item)
            }
            return
        }
        
        // Try to capture image
        if let imageData = getImageData(from: pasteboard) {
            let hash = imageData.hashValue
            
            // Skip consecutive duplicates
            if hash != lastContentHash {
                lastContentHash = hash
                
                // Save image to disk
                if let filename = store.saveImage(imageData) {
                    let item = ClipboardItem.image(filename: filename, sourceApp: sourceApp)
                    store.add(item)
                }
            }
        }
    }
    
    private func getImageData(from pasteboard: NSPasteboard) -> Data? {
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        
        for type in imageTypes {
            if let data = pasteboard.data(forType: type) {
                if let image = NSImage(data: data),
                   let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    return pngData
                }
                return data
            }
        }
        
        return nil
    }
}
