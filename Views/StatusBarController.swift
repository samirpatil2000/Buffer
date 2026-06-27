import Cocoa
import SwiftUI

/// Manages the menu bar status item - click to toggle window
class StatusBarController {
    private var statusItem: NSStatusItem
    private let store: ClipboardStore
    private let watcher: ClipboardWatcher
    private let onToggleHistory: () -> Void
    private var settingsWindowController: NSWindowController?
    private var activeAlert: NSAlert?
    
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
        
        // Show current shortcut
        let settings = SettingsManager.shared
        let shortcutDisplay = "\(settings.hotkeyModifiers.displayString)\(keyCodeNames[settings.hotkeyKeyCode] ?? "?")"
        let shortcutItem = NSMenuItem(title: "Shortcut: \(shortcutDisplay)", action: nil, keyEquivalent: "")
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())
        
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
    
    @objc private func checkForUpdates() {
        UpdateService.shared.checkForUpdates(silent: false)
    }

    @objc private func showSettings() {
        if let controller = settingsWindowController, let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
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
    
    @objc private func checkboxToggled(_ sender: NSButton) {
        guard let alert = activeAlert else { return }
        if sender.state == .on {
            alert.informativeText = "This will permanently delete all unpinned, unbookmarked, and untagged items."
        } else {
            alert.informativeText = "This will permanently delete all clipboard items, including pinned, bookmarked, and tagged items."
        }
    }
    
    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Clipboard History?"
        alert.informativeText = "This will permanently delete all unpinned, unbookmarked, and untagged items."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        
        let checkbox = NSButton(checkboxWithTitle: "Keep pinned, bookmarked, and tagged items", target: self, action: #selector(checkboxToggled(_:)))
        checkbox.state = .on
        checkbox.sizeToFit()
        checkbox.frame = NSRect(x: 0, y: 0, width: max(checkbox.frame.width, 350), height: 24)
        alert.accessoryView = checkbox
        
        activeAlert = alert
        
        if alert.runModal() == .alertFirstButtonReturn {
            let keepProtected = checkbox.state == .on
            store.clear(keepProtected: keepProtected)
        }
        
        activeAlert = nil
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
