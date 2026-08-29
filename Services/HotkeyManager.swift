import Cocoa
import Carbon

/// Identifiers for Buffer's global hotkeys.
/// Each registered hotkey needs a unique id so the shared Carbon event handler
/// knows which callback to fire.
enum HotkeyID: UInt32 {
    case showHistory = 1
    case captureToText = 2
}

/// Manages global keyboard shortcut registration using Carbon API
///
/// One instance per hotkey. Instances register themselves in a shared registry
/// keyed by `HotkeyID` so the single Carbon event handler can route key presses
/// to the right callback.
class HotkeyManager {
    private let id: HotkeyID
    private let callback: () -> Void

    /// Supplies the current key combination, or nil when the hotkey is disabled.
    private let binding: () -> (keyCode: UInt16, modifiers: HotkeyModifiers)?

    private var hotKeyRef: EventHotKeyRef?

    // Registry of live managers, so the C callback can find the right one
    private static var instances: [UInt32: HotkeyManager] = [:]
    private static var eventHandlerInstalled = false

    init(id: HotkeyID = .showHistory,
         binding: @escaping () -> (keyCode: UInt16, modifiers: HotkeyModifiers)?,
         callback: @escaping () -> Void) {
        self.id = id
        self.binding = binding
        self.callback = callback
        HotkeyManager.instances[id.rawValue] = self
    }

    /// Convenience initializer for the main history hotkey
    convenience init(callback: @escaping () -> Void) {
        self.init(
            id: .showHistory,
            binding: {
                let settings = SettingsManager.shared
                return (settings.hotkeyKeyCode, settings.hotkeyModifiers)
            },
            callback: callback
        )
    }

    func register() {
        unregister()

        guard let combo = binding() else {
            print("[HotkeyManager] \(id) is disabled — not registering")
            return
        }

        print("[HotkeyManager] Registering \(id): keyCode=\(combo.keyCode) mods=\(combo.modifiers.displayString)")

        guard HotkeyManager.installEventHandlerIfNeeded() else { return }

        var modifiers: UInt32 = 0
        if combo.modifiers.shift { modifiers |= UInt32(shiftKey) }
        if combo.modifiers.command { modifiers |= UInt32(cmdKey) }
        if combo.modifiers.option { modifiers |= UInt32(optionKey) }
        if combo.modifiers.control { modifiers |= UInt32(controlKey) }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4255_4646), id: id.rawValue) // "BUFF"

        let registerStatus = RegisterEventHotKey(
            UInt32(combo.keyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            print("[HotkeyManager] ✅ Carbon hotkey registered: \(id) keyCode=\(combo.keyCode)")
        } else {
            print("[HotkeyManager] ❌ Failed to register \(id): \(registerStatus)")
        }
    }

    func reregister() {
        register()
    }

    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
            print("[HotkeyManager] Hotkey unregistered: \(id)")
        }
    }

    /// Installs the process-wide Carbon handler once. Returns false if it could not be installed.
    private static func installEventHandlerIfNeeded() -> Bool {
        if eventHandlerInstalled { return true }

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

                let pressedID = hotKeyID.id
                print("[HotkeyManager] Carbon hotkey detected: id=\(pressedID)")
                DispatchQueue.main.async {
                    HotkeyManager.instances[pressedID]?.callback()
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
            return false
        }

        eventHandlerInstalled = true
        return true
    }

    deinit {
        unregister()
        HotkeyManager.instances[id.rawValue] = nil
    }
}
