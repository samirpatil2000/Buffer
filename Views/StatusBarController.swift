import Cocoa
import SwiftUI

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
    
    private var settingsWindow: NSWindow?
    
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
    
    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Buffer Settings"
            window.level = .floating  // Keep on top
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView())
            settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
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
