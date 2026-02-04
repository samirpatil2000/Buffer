import Cocoa
import Carbon

/// Manages global keyboard shortcut registration using Carbon API
class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private let callback: () -> Void
    
    // Store the singleton for the C callback
    private static var instance: HotkeyManager?
    
    // Shift + Command + V
    private let requiredKeyCode: UInt32 = 9 // V key
    
    init(callback: @escaping () -> Void) {
        self.callback = callback
        HotkeyManager.instance = self
    }
    
    func register() {
        print("[HotkeyManager] Registering hotkey using Carbon API...")
        
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
                    print("[HotkeyManager] Carbon hotkey detected! ⇧⌘V")
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
        
        // Register the hotkey: Shift + Command + V
        var hotKeyID = EventHotKeyID(signature: OSType(0x4255_4646), id: 1) // "BUFF"
        let modifiers: UInt32 = UInt32(shiftKey | cmdKey)
        
        let registerStatus = RegisterEventHotKey(
            requiredKeyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if registerStatus == noErr {
            print("[HotkeyManager] ✅ Carbon hotkey registered: ⇧⌘V (Shift+Command+V)")
        } else {
            print("[HotkeyManager] ❌ Failed to register hotkey: \(registerStatus)")
        }
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
