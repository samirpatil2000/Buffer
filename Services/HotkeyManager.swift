import Cocoa
import Carbon

/// Manages global keyboard shortcut registration using Carbon API
class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private let callback: () -> Void
    
    // Store weak reference to the active manager for the C callback
    private static weak var instance: HotkeyManager?
    private static var eventHandlerInstalled = false
    
    var isRegistered: Bool {
        hotKeyRef != nil
    }
    
    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
    
    func register(keyCode: UInt32? = nil, modifiers: UInt32? = nil) {
        let settings = SettingsManager.shared
        print("[HotkeyManager] Registering: keyCode=\(settings.hotkeyKeyCode) mods=\(settings.hotkeyModifiers.displayString)")
        
        // If another manager was active, unregister its Carbon hotkey first
        // to avoid eventHotKeyExistsErr (-9878) collisions.
        if let existing = HotkeyManager.instance, existing !== self {
            existing.unregister()
        }
        
        unregister()
        HotkeyManager.instance = self
        
        if !HotkeyManager.eventHandlerInstalled {
            // Install event handler on the application event target for continuous AppKit run loop delivery
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
        
        // Register the hotkey using GetEventDispatcherTarget()
        let requiredKeyCode: UInt32
        let requiredModifiers: UInt32
        
        if let keyCode = keyCode, let modifiers = modifiers {
            requiredKeyCode = keyCode
            requiredModifiers = modifiers
        } else {
            requiredKeyCode = UInt32(SettingsManager.shared.hotkeyKeyCode)
            let mods = SettingsManager.shared.hotkeyModifiers
            var modsMask: UInt32 = 0
            if mods.shift { modsMask |= UInt32(shiftKey) }
            if mods.command { modsMask |= UInt32(cmdKey) }
            if mods.option { modsMask |= UInt32(optionKey) }
            if mods.control { modsMask |= UInt32(controlKey) }
            requiredModifiers = modsMask
        }
        
        var hotKeyID = EventHotKeyID(signature: OSType(0x4255_4646), id: 1) // "BUFF"
        
        let registerStatus = RegisterEventHotKey(
            requiredKeyCode,
            requiredModifiers,
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
        if HotkeyManager.instance === self {
            HotkeyManager.instance = nil
        }
    }
    
    deinit {
        unregister()
    }
}
