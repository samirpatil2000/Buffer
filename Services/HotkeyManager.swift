import Cocoa
import Carbon
import os

/// Manages global keyboard shortcut registration using Carbon API.
///
/// Secure Input and why there is a second shortcut
/// -----------------------------------------------
/// While any app has Secure Input on, macOS does not deliver a global shortcut
/// that has neither ⌘ nor ⌃ (for example ⌥C). The key is typed into the focused
/// field instead (⌥C becomes "ç") and Buffer is never told. Secure Input is on
/// while a password field has focus, and Chromium browsers leave it on after you
/// click out of one until the tab or window changes.
///
/// This was measured with real key presses on macOS 26.6:
///   - Secure Input off: ⌥J, ⌥K and ⌃⌥J all fire.
///   - Secure Input on:  ⌥J and ⌥K never fire, ⌃⌥J still fires.
///   - `GetApplicationEventTarget()` and `GetEventDispatcherTarget()` behave the
///     same in both cases. The event target is NOT the cause; do not switch it
///     to "fix" password fields.
///
/// No user-level API can receive an Option-only key under Secure Input (event
/// taps and global monitors are blocked too), so when the user's shortcut is in
/// that class Buffer also registers the same key with ⌃ added. That companion
/// keeps working in password fields.
class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var companionHotKeyRef: EventHotKeyRef?
    private let callback: () -> Void

    // Store weak reference to the active manager for the C callback
    private static weak var instance: HotkeyManager?
    private static var eventHandlerInstalled = false

    private static let signature = OSType(0x4255_4646) // "BUFF"
    private static let primaryID: UInt32 = 1
    private static let companionID: UInt32 = 2

    /// Visible with: log show --last 1h --predicate 'subsystem == "com.samirpatil.Buffer"'
    private static let log = Logger(subsystem: "com.samirpatil.Buffer", category: "hotkey")

    var isRegistered: Bool {
        hotKeyRef != nil
    }

    /// True when the ⌃ companion for an Option/Shift-only shortcut is registered.
    var isCompanionRegistered: Bool {
        companionHotKeyRef != nil
    }

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    /// Carbon modifiers for the companion shortcut, or nil when the shortcut
    /// already contains ⌘ or ⌃ and so is delivered under Secure Input as is.
    static func secureInputCompanionModifiers(for modifiers: UInt32) -> UInt32? {
        let deliveredUnderSecureInput = UInt32(cmdKey) | UInt32(controlKey)
        guard modifiers & deliveredUnderSecureInput == 0 else { return nil }
        return modifiers | UInt32(controlKey)
    }

    static func carbonModifiers(from mods: HotkeyModifiers) -> UInt32 {
        var mask: UInt32 = 0
        if mods.shift { mask |= UInt32(shiftKey) }
        if mods.command { mask |= UInt32(cmdKey) }
        if mods.option { mask |= UInt32(optionKey) }
        if mods.control { mask |= UInt32(controlKey) }
        return mask
    }

    func register(keyCode: UInt32? = nil, modifiers: UInt32? = nil) {
        // If another manager was active, unregister its Carbon hotkey first
        // to avoid eventHotKeyExistsErr (-9878) collisions.
        if let existing = HotkeyManager.instance, existing !== self {
            existing.unregister()
        }

        unregister()
        HotkeyManager.instance = self

        guard installEventHandlerIfNeeded() else { return }

        let requiredKeyCode: UInt32
        let requiredModifiers: UInt32

        if let keyCode = keyCode, let modifiers = modifiers {
            requiredKeyCode = keyCode
            requiredModifiers = modifiers
        } else {
            requiredKeyCode = UInt32(SettingsManager.shared.hotkeyKeyCode)
            requiredModifiers = HotkeyManager.carbonModifiers(from: SettingsManager.shared.hotkeyModifiers)
        }

        let primaryStatus = RegisterEventHotKey(
            requiredKeyCode,
            requiredModifiers,
            EventHotKeyID(signature: HotkeyManager.signature, id: HotkeyManager.primaryID),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if primaryStatus == noErr {
            HotkeyManager.log.notice("Shortcut registered: keyCode=\(requiredKeyCode) modifiers=\(requiredModifiers)")
        } else {
            HotkeyManager.log.error("Shortcut registration FAILED: keyCode=\(requiredKeyCode) modifiers=\(requiredModifiers) status=\(primaryStatus)")
        }

        guard let companionModifiers = HotkeyManager.secureInputCompanionModifiers(for: requiredModifiers) else {
            return
        }

        let companionStatus = RegisterEventHotKey(
            requiredKeyCode,
            companionModifiers,
            EventHotKeyID(signature: HotkeyManager.signature, id: HotkeyManager.companionID),
            GetApplicationEventTarget(),
            0,
            &companionHotKeyRef
        )

        if companionStatus == noErr {
            HotkeyManager.log.notice("Password-field companion registered: keyCode=\(requiredKeyCode) modifiers=\(companionModifiers)")
        } else {
            HotkeyManager.log.error("Password-field companion registration FAILED: status=\(companionStatus)")
        }
    }

    private func installEventHandlerIfNeeded() -> Bool {
        if HotkeyManager.eventHandlerInstalled { return true }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, theEvent, _) -> OSStatus in
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

                guard hotKeyID.signature == HotkeyManager.signature,
                      hotKeyID.id == HotkeyManager.primaryID || hotKeyID.id == HotkeyManager.companionID else {
                    return OSStatus(eventNotHandledErr)
                }

                let viaCompanion = hotKeyID.id == HotkeyManager.companionID
                let secureInputOn = IsSecureEventInputEnabled()
                HotkeyManager.log.notice("Shortcut pressed (companion=\(viaCompanion), secureInput=\(secureInputOn))")
                DispatchQueue.main.async {
                    HotkeyManager.instance?.callback()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )

        if status != noErr {
            HotkeyManager.log.error("Failed to install hotkey event handler: status=\(status)")
            return false
        }
        HotkeyManager.eventHandlerInstalled = true
        return true
    }

    func reregister() {
        register()
    }

    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let companionHotKeyRef = companionHotKeyRef {
            UnregisterEventHotKey(companionHotKeyRef)
            self.companionHotKeyRef = nil
        }
        if HotkeyManager.instance === self {
            HotkeyManager.instance = nil
        }
    }

    deinit {
        unregister()
    }
}
