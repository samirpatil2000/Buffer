import Cocoa
import Carbon.HIToolbox

/// Manages global keyboard shortcut registration
class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let callback: () -> Void
    
    // Shift + Command + V
    private let requiredModifiers: CGEventFlags = [.maskShift, .maskCommand]
    private let requiredKeyCode: CGKeyCode = 9 // V key
    
    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
    
    func register() {
        // Create event tap to listen for key events
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        // Store self reference for callback
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                
                // Check if this is our hotkey
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                
                // Check for Shift + Command + V
                if keyCode == manager.requiredKeyCode &&
                    flags.contains(.maskShift) &&
                    flags.contains(.maskCommand) &&
                    !flags.contains(.maskControl) &&
                    !flags.contains(.maskAlternate) {
                    
                    // Execute callback on main thread
                    DispatchQueue.main.async {
                        manager.callback()
                    }
                    
                    // Consume the event
                    return nil
                }
                
                return Unmanaged.passRetained(event)
            },
            userInfo: refcon
        )
        
        guard let eventTap = eventTap else {
            print("Failed to create event tap. Accessibility permissions may be required.")
            requestAccessibilityPermissions()
            return
        }
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    func unregister() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
    
    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
