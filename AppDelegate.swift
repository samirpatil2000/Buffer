import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var clipboardWatcher: ClipboardWatcher?
    private var historyWindowController: HistoryWindowController?
    private var hotkeyManager: HotkeyManager?
    
    let clipboardStore = ClipboardStore()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - we're menu bar only
        NSApp.setActivationPolicy(.accessory)
        _ = ActiveApplicationMonitor.shared
        
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hasLaunchedBefore") {
            // Give it a tiny delay to ensure everything is loaded before registering SMAppService
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                SettingsManager.shared.toggleLaunchAtLogin(true)
                defaults.set(true, forKey: "hasLaunchedBefore")
            }
        }
        
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
        
        // Setup global hotkey (Shift + Command + V)
        hotkeyManager = HotkeyManager { [weak self] in
            self?.toggleHistoryWindow()
        }
        hotkeyManager?.register()
        
        NotificationCenter.default.addObserver(forName: .bufferHotkeyChanged, object: nil, queue: .main) { [weak self] _ in
            self?.hotkeyManager?.reregister()
        }

        DispatchQueue.main.async { [weak self] in
            self?.showHistoryWindow(focusSearch: true, activateApp: false)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        clipboardWatcher?.stopWatching()
        hotkeyManager?.unregister()
    }
    
    private func toggleHistoryWindow() {
        print("[AppDelegate] toggleHistoryWindow called")
        let historyWindowController = historyWindowController ?? makeHistoryWindowController()
        if let window = historyWindowController.window, window.isVisible {
            print("[AppDelegate] Window is visible, closing...")
            historyWindowController.close()
        } else {
            print("[AppDelegate] Window is hidden, showing...")
            showHistoryWindow()
        }
    }
    
    private func showHistoryWindow(
        focusSearch: Bool = true,
        activateApp: Bool = true
    ) {
        let historyWindowController = historyWindowController ?? makeHistoryWindowController()
        historyWindowController.showWindow(
            nil,
            focusSearch: focusSearch,
            activateApp: activateApp
        )
    }

    private func makeHistoryWindowController() -> HistoryWindowController {
        let controller = HistoryWindowController(store: clipboardStore)
        historyWindowController = controller
        return controller
    }
}
