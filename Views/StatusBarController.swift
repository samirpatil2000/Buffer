import Cocoa

/// Manages the menu bar status item - click to toggle window
class StatusBarController {
    private var statusItem: NSStatusItem
    private let store: ClipboardStore
    private let watcher: ClipboardWatcher
    private let onToggleHistory: () -> Void
    
    init(store: ClipboardStore, watcher: ClipboardWatcher, onShowHistory: @escaping () -> Void) {
        self.store = store
        self.watcher = watcher
        self.onToggleHistory = onShowHistory
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        setupButton()
    }
    
    private func setupButton() {
        guard let button = statusItem.button else { return }
        
        // Use SF Symbol for clipboard
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Buffer")
        image?.isTemplate = true
        button.image = image?.withSymbolConfiguration(config)
        
        // Direct click action - no menu
        button.action = #selector(handleClick)
        button.target = self
        
        // Right-click for menu
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    
    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            onToggleHistory()
            return
        }
        
        if event.type == .rightMouseUp {
            // Show context menu on right click
            showContextMenu()
        } else {
            // Toggle history on left click
            onToggleHistory()
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        // Pause/Resume
        let pauseTitle = watcher.isPaused ? "Resume Capture" : "Pause Capture"
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Clear History
        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit Buffer", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // Reset so left click works
    }
    
    @objc private func togglePause() {
        if watcher.isPaused {
            watcher.resume()
            updateIcon(paused: false)
        } else {
            watcher.pause()
            updateIcon(paused: true)
        }
    }
    
    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Clipboard History?"
        alert.informativeText = "This will permanently delete all clipboard items."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear()
        }
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    private func updateIcon(paused: Bool) {
        guard let button = statusItem.button else { return }
        
        let symbolName = paused ? "doc.on.clipboard.fill" : "doc.on.clipboard"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Buffer")
        image?.isTemplate = true
        button.image = image?.withSymbolConfiguration(config)
    }
}
