import Cocoa
import SwiftUI
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var clipboardWatcher: ClipboardWatcher?
    private var historyWindowController: HistoryWindowController?
    var hotkeyManager: HotkeyManager?
    private var settingsWindowController: NSWindowController?
    
    let clipboardStore = ClipboardStore()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - we're menu bar only
        NSApp.setActivationPolicy(.accessory)
        
        // Apply saved theme preference
        SettingsManager.shared.applyTheme()
        
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hasLaunchedBefore") {
            // Give it a tiny delay to ensure everything is loaded before registering SMAppService
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                SettingsManager.shared.toggleLaunchAtLogin(true)
                defaults.set(true, forKey: "hasLaunchedBefore")
            }
        }
        
        // Request Accessibility permissions for global hotkeys
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
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
        
        NotificationCenter.default.addObserver(forName: .bufferHotkeyChanged, object: nil, queue: .main) { [weak self] _ in
            self?.hotkeyManager?.reregister()
        }

        NotificationCenter.default.addObserver(forName: .bufferOpenHistoryWindow, object: nil, queue: .main) { [weak self] _ in
            self?.showHistoryWindow()
        }

        NotificationCenter.default.addObserver(forName: .bufferOpenSettingsWindow, object: nil, queue: .main) { [weak self] _ in
            self?.showSettingsWindow()
        }

        NotificationCenter.default.addObserver(forName: .bufferThemeChanged, object: nil, queue: .main) { [weak self] _ in
            self?.settingsWindowController?.window?.appearance = SettingsManager.shared.appTheme.nsAppearance
            self?.settingsWindowController?.window?.contentView?.appearance = SettingsManager.shared.appTheme.nsAppearance
        }

        UpdateService.shared.checkIfJustUpdated()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            UpdateService.shared.checkOnLaunchIfNeeded()
            UpdateService.shared.startPeriodicChecking()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let window = historyWindowController?.window {
            window.saveFrame(usingName: HistoryWindowController.windowAutosaveName)
        }
        UpdateService.shared.stopPeriodicChecking()
        clipboardWatcher?.stopWatching()
        hotkeyManager?.unregister()
        print("[AppDelegate] applicationWillTerminate — call stack:")
        Thread.callStackSymbols.forEach { print($0) }
    }
    
    func toggleHistoryWindow() {
        print("[AppDelegate] toggleHistoryWindow called")
        if let window = historyWindowController?.window, window.isVisible, window.isKeyWindow {
            print("[AppDelegate] Window is visible and key, closing...")
            historyWindowController?.close()
        } else {
            if isPasswordFieldFocused() {
                print("[AppDelegate] Password field focused; suppressing window show.")
                return
            }
            print("[AppDelegate] Window is hidden or not key, showing...")
            showHistoryWindow()
        }
    }
    
    func isPasswordFieldFocused() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return false
        }
        
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement else {
            // Also check system-wide focused element fallback
            let systemWide = AXUIElementCreateSystemWide()
            var sysFocused: CFTypeRef?
            if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &sysFocused) == .success,
               let sysElement = sysFocused {
                return isSecureElement(sysElement as! AXUIElement)
            }
            return false
        }
        
        return isSecureElement(element as! AXUIElement)
    }
    
    func isSecureElement(_ element: AXUIElement) -> Bool {
        // If the element provides an AXFocused attribute and explicitly reports false,
        // it means the element is not currently focused (e.g. user clicked outside onto whitespace/canvas).
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &focusedRef) == .success,
           let isFocused = focusedRef as? Bool, !isFocused {
            return false
        }
        
        var subrole: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
           let subroleString = subrole as? String, subroleString == "AXSecureTextField" {
            return true
        }
        
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           let roleString = role as? String, roleString == "AXSecureTextField" {
            return true
        }
        
        return false
    }
    
    private func showHistoryWindow() {
        historyWindowController?.showWindow(nil)
    }

    private func showSettingsWindow() {
        if let controller = settingsWindowController, let window = controller.window {
            positionOnActiveScreen(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.appearance = SettingsManager.shared.appTheme.nsAppearance
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .participatesInCycle]
        positionOnActiveScreen(window)
        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func positionOnActiveScreen(_ window: NSWindow) {
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - (window.frame.width / 2)
            let y = screenRect.midY - (window.frame.height / 2)
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }
    }
}
