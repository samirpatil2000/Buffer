import SwiftUI

/// Settings view for configuring Buffer preferences
struct SettingsView: View {
    @StateObject private var settings = SettingsViewModel()
    @State private var isRecording = false
    @State private var recordedKeyCode: UInt16 = 0
    @State private var recordedModifiers = HotkeyModifiers()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                Text("Buffer Settings")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            
            Divider()
            
            // Hotkey section
            VStack(alignment: .leading, spacing: 12) {
                Text("Keyboard Shortcut")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    // Current shortcut display
                    HStack(spacing: 4) {
                        Text(settings.hotkeyModifiers.displayString)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                        Text(keyCodeNames[settings.hotkeyKeyCode] ?? "?")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isRecording ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    
                    Button(action: { isRecording.toggle() }) {
                        Text(isRecording ? "Cancel" : "Change")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
                
                if isRecording {
                    Text("Press your new shortcut...")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                }
            }
            
            Divider()
            
            // Preset shortcuts
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Presets")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    presetButton(label: "⇧⌘V", mods: HotkeyModifiers(shift: true, command: true), keyCode: 9)
                    presetButton(label: "⌥⌘V", mods: HotkeyModifiers(command: true, option: true), keyCode: 9)
                    presetButton(label: "⌃⇧V", mods: HotkeyModifiers(shift: true, control: true), keyCode: 9)
                    presetButton(label: "⌘B", mods: HotkeyModifiers(command: true), keyCode: 11)
                }
            }
            
            Spacer()
            
            // Footer
            Text("Changes take effect after restarting Buffer")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 320, height: 280)
        .background(KeyRecorder(isRecording: $isRecording) { keyCode, modifiers in
            settings.hotkeyKeyCode = keyCode
            settings.hotkeyModifiers = modifiers
            settings.save()
            isRecording = false
        })
    }
    
    private func presetButton(label: String, mods: HotkeyModifiers, keyCode: UInt16) -> some View {
        Button(action: {
            settings.hotkeyModifiers = mods
            settings.hotkeyKeyCode = keyCode
            settings.save()
        }) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
    }
}

/// Records keyboard shortcuts when active
struct KeyRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecord: (UInt16, HotkeyModifiers) -> Void
    
    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.onRecord = onRecord
        return view
    }
    
    func updateNSView(_ nsView: KeyRecorderView, context: Context) {
        nsView.isRecording = isRecording
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class KeyRecorderView: NSView {
    var isRecording = false
    var onRecord: ((UInt16, HotkeyModifiers) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        
        // Ignore modifier-only presses
        if event.keyCode == 56 || event.keyCode == 59 || event.keyCode == 58 || event.keyCode == 55 {
            return
        }
        
        let mods = HotkeyModifiers(
            shift: event.modifierFlags.contains(.shift),
            command: event.modifierFlags.contains(.command),
            option: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control)
        )
        
        // Require at least one modifier
        if mods.shift || mods.command || mods.option || mods.control {
            onRecord?(event.keyCode, mods)
        }
    }
}

/// ViewModel wrapper for SettingsManager to avoid crashes
class SettingsViewModel: ObservableObject {
    @Published var hotkeyModifiers: HotkeyModifiers
    @Published var hotkeyKeyCode: UInt16
    
    private let defaults = UserDefaults.standard
    private let hotkeyModifiersKey = "hotkeyModifiers"
    private let hotkeyKeyCodeKey = "hotkeyKeyCode"
    
    init() {
        // Load modifiers
        if let savedMods = defaults.array(forKey: hotkeyModifiersKey) as? [String] {
            self.hotkeyModifiers = HotkeyModifiers(from: savedMods)
        } else {
            self.hotkeyModifiers = HotkeyModifiers(shift: true, command: true, option: false, control: false)
        }
        
        // Load keycode (default to V = 9)
        let savedKeyCode = defaults.integer(forKey: hotkeyKeyCodeKey)
        self.hotkeyKeyCode = savedKeyCode > 0 ? UInt16(savedKeyCode) : 9
    }
    
    func save() {
        defaults.set(hotkeyModifiers.toArray(), forKey: hotkeyModifiersKey)
        defaults.set(Int(hotkeyKeyCode), forKey: hotkeyKeyCodeKey)
    }
}
