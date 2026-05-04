import Cocoa
import Carbon

/// Manages global keyboard shortcut registration using Carbon API
class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private let callback: () -> Void
    
    // Store the singleton for the C callback
    private static var instance: HotkeyManager?
    private static var eventHandlerInstalled = false
    
    init(callback: @escaping () -> Void) {
        self.callback = callback
        HotkeyManager.instance = self
    }
    
    func register() {
        let settings = SettingsManager.shared
        print("[HotkeyManager] Registering: keyCode=\(settings.hotkeyKeyCode) mods=\(settings.hotkeyModifiers.displayString)")
        
        unregister()
        
        if !HotkeyManager.eventHandlerInstalled {
            // Install event handler
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { (nextHandler, theEvent, userData) -> OSStatus in
                    var hotKeyID = EventHotKeyID()
                    GetEventParameter(
                        theEvent,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID
                    )
                    
                    if hotKeyID.id == 1 {
                        print("[HotkeyManager] Carbon hotkey detected!")
                        DispatchQueue.main.async {
                            HotkeyManager.instance?.callback()
                        }
                    }
                    
                    return noErr
                },
                1,
                &eventType,
                nil,
                nil
            )
            
            if status != noErr {
                print("[HotkeyManager] ❌ Failed to install event handler: \(status)")
                return
            }
            HotkeyManager.eventHandlerInstalled = true
        }
        
        // Register the hotkey
        let requiredKeyCode = UInt32(SettingsManager.shared.hotkeyKeyCode)
        let mods = SettingsManager.shared.hotkeyModifiers
        var modifiers: UInt32 = 0
        if mods.shift { modifiers |= UInt32(shiftKey) }
        if mods.command { modifiers |= UInt32(cmdKey) }
        if mods.option { modifiers |= UInt32(optionKey) }
        if mods.control { modifiers |= UInt32(controlKey) }
        
        let hotKeyID = EventHotKeyID(signature: OSType(0x4255_4646), id: 1) // "BUFF"
        
        let registerStatus = RegisterEventHotKey(
            requiredKeyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if registerStatus == noErr {
            print("[HotkeyManager] ✅ Carbon hotkey registered: keyCode=\(requiredKeyCode)")
        } else {
            print("[HotkeyManager] ❌ Failed to register hotkey: \(registerStatus)")
        }
    }
    
    func reregister() {
        register()
    }
    
    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
            print("[HotkeyManager] Hotkey unregistered")
        }
    }
    
    deinit {
        unregister()
        HotkeyManager.instance = nil
    }
}
