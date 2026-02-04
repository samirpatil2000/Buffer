import Cocoa
import SwiftUI
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var clipboardWatcher: ClipboardWatcher?
    private var historyWindowController: HistoryWindowController?
    private var hotkeyManager: HotkeyManager?
    
    let clipboardStore = ClipboardStore()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - we're menu bar only
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize clipboard watcher
        clipboardWatcher = ClipboardWatcher(store: clipboardStore)
        clipboardWatcher?.startWatching()
        
        // Initialize status bar
        statusBarController = StatusBarController(
            store: clipboardStore,
            watcher: clipboardWatcher!,
            onShowHistory: { [weak self] in
                self?.showHistoryWindow()
            }
        )
        
        // Initialize history window controller
        historyWindowController = HistoryWindowController(store: clipboardStore)
        
        // Setup global hotkey (Shift + Command + V)
        hotkeyManager = HotkeyManager { [weak self] in
            self?.toggleHistoryWindow()
        }
        hotkeyManager?.register()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        clipboardWatcher?.stopWatching()
        hotkeyManager?.unregister()
    }
    
    private func toggleHistoryWindow() {
        print("[AppDelegate] toggleHistoryWindow called")
        if let window = historyWindowController?.window, window.isVisible {
            print("[AppDelegate] Window is visible, closing...")
            historyWindowController?.close()
        } else {
            print("[AppDelegate] Window is hidden, showing...")
            showHistoryWindow()
        }
    }
    
    private func showHistoryWindow() {
        historyWindowController?.showWindow(nil)
    }
}
