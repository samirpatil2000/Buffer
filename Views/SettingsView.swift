import SwiftUI

/// Settings view for configuring Buffer preferences
struct SettingsView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    @StateObject private var settings = SettingsViewModel()
    @State private var isRecording = false
    @State private var recordedKeyCode: UInt16 = 0
    @State private var recordedModifiers = HotkeyModifiers()
    @State private var showingTrimAlert = false
    @State private var pendingTier: HistoryLimit?
    
    var body: some View {
        VStack(spacing: 12) {
            // Centered Segmented Tab Picker
            Picker("", selection: $settingsManager.selectedSettingsTab) {
                Text("General").tag(0)
                Text("Shortcuts").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            .padding(.top, 14)
            
            Divider()
                .padding(.horizontal, 16)
                .opacity(0.5)
            
            if settingsManager.selectedSettingsTab == 0 {
                ScrollView(.vertical, showsIndicators: false) {
                    generalSettingsTab
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    ShortcutsCheatSheetView(isEmbeddedInSettings: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                }
            }
        }
        .frame(width: 460, height: 560)
        .alert("Reduce History Limit?", isPresented: $showingTrimAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reduce & Delete", role: .destructive) {
                if let tier = pendingTier {
                    settings.historyLimit = tier
                    settings.save()
                }
            }
        } message: {
            Text("This will permanently delete your oldest unbookmarked items to fit the new size. This action cannot be undone.")
        }
        .background(KeyRecorder(isRecording: $isRecording) { keyCode, modifiers in
            settings.hotkeyKeyCode = keyCode
            settings.hotkeyModifiers = modifiers
            settings.save()
            isRecording = false
        })
    }
    
    // MARK: - General Tab
    
    private var generalSettingsTab: some View {
        VStack(spacing: 18) {
            // 1. Appearance Card
            settingsCard(title: "APPEARANCE") {
                HStack(spacing: 16) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                settings.appTheme = theme
                                settings.save()
                            }
                        }) {
                            ThemePreviewThumbnail(
                                theme: theme,
                                isSelected: settings.appTheme == theme
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            
            // 2. Global Shortcut Card
            settingsCard(title: "GLOBAL SHORTCUT") {
                settingsRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Activation Hotkey")
                            .font(.system(size: 13, weight: .medium))
                        if isRecording {
                            Text("Press your new shortcut…")
                                .font(.system(size: 11))
                                .foregroundColor(.accentColor)
                        } else {
                            Text("Brings Buffer to front")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        // Current shortcut badge
                        HStack(spacing: 4) {
                            Text(settings.hotkeyModifiers.displayString)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            Text(keyCodeNames[settings.hotkeyKeyCode] ?? "?")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isRecording ? Color.accentColor.opacity(0.18) : Color(NSColor.windowBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(isRecording ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
                        )
                        
                        Button(isRecording ? "Cancel" : "Change") {
                            isRecording.toggle()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Menu {
                            Button("⇧⌘V  (Shift-Command-V)") {
                                applyPreset(mods: HotkeyModifiers(shift: true, command: true), keyCode: 9)
                            }
                            Button("⌥⌘V  (Option-Command-V)") {
                                applyPreset(mods: HotkeyModifiers(command: true, option: true), keyCode: 9)
                            }
                            Button("⌃⇧V  (Control-Shift-V)") {
                                applyPreset(mods: HotkeyModifiers(shift: true, control: true), keyCode: 9)
                            }
                            Button("⌘B    (Command-B)") {
                                applyPreset(mods: HotkeyModifiers(command: true), keyCode: 11)
                            }
                        } label: {
                            Text("Presets")
                                .font(.system(size: 12))
                        }
                        .menuStyle(.borderedButton)
                        .controlSize(.small)
                        .fixedSize()
                    }
                }
            }
            
            // 3. System Card
            settingsCard(title: "SYSTEM") {
                settingsRow {
                    Text("Launch at Login")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: settings.launchAtLogin) { newValue in
                            SettingsManager.shared.toggleLaunchAtLogin(newValue)
                            DispatchQueue.main.async {
                                settings.launchAtLogin = SettingsManager.shared.launchAtLogin
                            }
                        }
                }
                
                rowDivider
                
                settingsRow {
                    Text("Hide Menu Bar Icon")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Toggle("", isOn: $settings.hideStatusBar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: settings.hideStatusBar) { _ in
                            settings.save()
                        }
                }
                
                rowDivider
                
                settingsRow {
                    Text("Include Pre-release Updates")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Toggle("", isOn: $settings.includePrereleases)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: settings.includePrereleases) { newValue in
                            settings.save()
                            if newValue {
                                UpdateService.shared.checkForUpdates(silent: true)
                            }
                        }
                }
            }
            
            // 4. Clipboard & History Card
            settingsCard(title: "CLIPBOARD & HISTORY") {
                // History Limit Picker
                VStack(spacing: 0) {
                    settingsRow {
                        Text("History Limit")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.historyLimit },
                            set: { tier in
                                if tier.isReduction(from: settings.historyLimit) {
                                    pendingTier = tier
                                    showingTrimAlert = true
                                } else {
                                    settings.historyLimit = tier
                                    settings.save()
                                }
                            }
                        )) {
                            ForEach(HistoryLimit.allCases, id: \.self) { tier in
                                Text(historyLimitTitle(for: tier)).tag(tier)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 175)
                    }
                    
                    if settings.historyLimit == .custom {
                        Divider().padding(.leading, 14).opacity(0.4)
                        settingsRow {
                            Text("Custom Limit")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.leading, 6)
                            Spacer()
                            HStack(spacing: 6) {
                                TextField("", value: $settings.customHistoryLimit, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                                    .onChange(of: settings.customHistoryLimit) { newValue in
                                        let clamped = max(1, newValue)
                                        if clamped != newValue {
                                            settings.customHistoryLimit = clamped
                                        }
                                        HistoryLimit.customHistoryLimit = clamped
                                        settings.save()
                                    }
                                Text("items")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                rowDivider
                
                // Deduplicate
                settingsRow {
                    Text("Deduplicate History")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Toggle("", isOn: $settings.deduplicateHistory)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: settings.deduplicateHistory) { _ in
                            settings.save()
                        }
                }
                
                rowDivider
                
                // Min text length
                settingsRow {
                    Text("Ignore Entries Shorter Than")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Stepper(
                        settings.minTextLength == 1
                            ? "1 character"
                            : "\(settings.minTextLength) characters",
                        value: $settings.minTextLength,
                        in: 1...20
                    )
                    .font(.system(size: 12))
                    .onChange(of: settings.minTextLength) { _ in
                        settings.save()
                    }
                }

                rowDivider

                // Ignore password manager copies
                settingsRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ignore Password Manager Copies")
                            .font(.system(size: 13, weight: .medium))
                        Text("Skips copies that password managers mark as private")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.ignoreConcealed)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: settings.ignoreConcealed) { _ in
                            settings.save()
                        }
                }

                rowDivider

                // Auto OCR
                settingsRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Extract Text from Images (OCR)")
                            .font(.system(size: 13, weight: .medium))
                        Text("Makes text inside copied screenshots searchable")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.autoOCR)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: settings.autoOCR) { _ in
                            settings.save()
                        }
                }
                .help("Uses on-device text recognition so screenshots and copied images become searchable automatically.")

                rowDivider
                
                // Preserve Rich Text
                settingsRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preserve Rich Text Formatting")
                            .font(.system(size: 13, weight: .medium))
                        Text("Stores styled text (RTF/HTML) and embedded images")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.preserveRichText)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: settings.preserveRichText) { _ in
                            settings.save()
                        }
                }
                .help("Stores styled text (RTF/HTML) and images embedded in copied text alongside the plain text.")
                
                rowDivider
                
                // Remote Images
                settingsRow {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("Download Remote Web Images")
                                .font(.system(size: 13, weight: .medium))
                            
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .help("Makes network requests on copy. Images in web pages are remote links; downloading them fetches data from the web (can load tracking pixels). Off by default.")
                        }
                        Text("Captures pictures referenced in copied web HTML")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.downloadRemoteImages)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!settings.preserveRichText)
                        .onChange(of: settings.downloadRemoteImages) { _ in
                            settings.save()
                        }
                }
            }
            
            // 5. About Section
            aboutSection
        }
    }
    
    // MARK: - Inset Group Helpers
    
    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    private func settingsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    private var rowDivider: some View {
        Divider()
            .padding(.leading, 14)
            .opacity(0.5)
    }
    
    private func historyLimitTitle(for tier: HistoryLimit) -> String {
        switch tier {
        case .essential: return "Essential (200)"
        case .deep:      return "Deep (1,000)"
        case .unlimited: return "Unlimited"
        case .custom:    return "Custom…"
        }
    }
    
    private func applyPreset(mods: HotkeyModifiers, keyCode: UInt16) {
        settings.hotkeyModifiers = mods
        settings.hotkeyKeyCode = keyCode
        settings.save()
    }
    
    // MARK: - About
    
    private var aboutSection: some View {
        VStack(spacing: 6) {
            Text("Designed to disappear. Built to remember.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
                .italic()

            Text("Buffer \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · by @samirpatil2000")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.5))

            HStack(spacing: 8) {
                Link("⭐ Star on GitHub", destination: URL(string: "https://github.com/samirpatil2000/Buffer")!)
                    .font(.system(size: 10, weight: .medium))

                Text("·")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.4))

                Link("Report an Issue", destination: URL(string: "https://github.com/samirpatil2000/Buffer/issues/new")!)
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 4)
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
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = self.window {
            // Set level to be above other apps but below system items
            window.level = .floating
            
            // Use a tiny delay to allow the window to be properly added to the window list
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
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

/// Visual macOS-style appearance thumbnail preview (Steve Jobs / Apple System Settings design)
struct ThemePreviewThumbnail: View {
    let theme: AppTheme
    let isSelected: Bool
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 7) {
            // Mini window representation
            ZStack {
                switch theme {
                case .light:
                    lightWindow
                case .dark:
                    darkWindow
                case .system:
                    splitWindow
                }
            }
            .frame(width: 86, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.24) : Color.primary.opacity(0.12)),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.16 : (isHovered ? 0.08 : 0.04)), radius: isSelected ? 3 : 1.5, y: 1)
            
            // Label
            Text(theme.label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
    
    // Light Window Preview
    private var lightWindow: some View {
        VStack(spacing: 0) {
            // Window titlebar
            HStack(spacing: 2.5) {
                trafficLights
                Spacer()
            }
            .padding(.horizontal, 5)
            .frame(height: 12)
            .background(Color(red: 0.90, green: 0.90, blue: 0.92))
            
            // Content
            VStack(alignment: .leading, spacing: 3) {
                mockRow(color: Color(red: 0.72, green: 0.72, blue: 0.76), width: 34)
                mockRow(color: Color(red: 0.84, green: 0.84, blue: 0.87), width: 54)
                mockRow(color: Color(red: 0.88, green: 0.88, blue: 0.90), width: 42)
            }
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
        }
    }
    
    // Dark Window Preview
    private var darkWindow: some View {
        VStack(spacing: 0) {
            // Window titlebar
            HStack(spacing: 2.5) {
                trafficLights
                Spacer()
            }
            .padding(.horizontal, 5)
            .frame(height: 12)
            .background(Color(red: 0.22, green: 0.22, blue: 0.24))
            
            // Content
            VStack(alignment: .leading, spacing: 3) {
                mockRow(color: Color(red: 0.52, green: 0.52, blue: 0.56), width: 34)
                mockRow(color: Color(red: 0.36, green: 0.36, blue: 0.40), width: 54)
                mockRow(color: Color(red: 0.30, green: 0.30, blue: 0.34), width: 42)
            }
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 0.13, green: 0.13, blue: 0.15))
        }
    }
    
    // Split Window Preview (Auto/System)
    private var splitWindow: some View {
        HStack(spacing: 0) {
            // Left half: Light
            VStack(spacing: 0) {
                HStack(spacing: 2.5) {
                    trafficLights
                    Spacer()
                }
                .padding(.leading, 5)
                .frame(height: 12)
                .background(Color(red: 0.90, green: 0.90, blue: 0.92))
                
                VStack(alignment: .leading, spacing: 3) {
                    mockRow(color: Color(red: 0.72, green: 0.72, blue: 0.76), width: 22)
                    mockRow(color: Color(red: 0.84, green: 0.84, blue: 0.87), width: 30)
                    mockRow(color: Color(red: 0.88, green: 0.88, blue: 0.90), width: 18)
                }
                .padding(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.white)
            }
            .frame(width: 43)
            
            // Right half: Dark
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                }
                .frame(height: 12)
                .background(Color(red: 0.22, green: 0.22, blue: 0.24))
                
                VStack(alignment: .leading, spacing: 3) {
                    mockRow(color: Color(red: 0.52, green: 0.52, blue: 0.56), width: 22)
                    mockRow(color: Color(red: 0.36, green: 0.36, blue: 0.40), width: 30)
                    mockRow(color: Color(red: 0.30, green: 0.30, blue: 0.34), width: 18)
                }
                .padding(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(red: 0.13, green: 0.13, blue: 0.15))
            }
            .frame(width: 43)
        }
    }
    
    private var trafficLights: some View {
        HStack(spacing: 2.5) {
            Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.33)).frame(width: 3.5, height: 3.5)
            Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 3.5, height: 3.5)
            Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 3.5, height: 3.5)
        }
    }
    
    private func mockRow(color: Color, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: width, height: 4)
    }
}

/// ViewModel wrapper for SettingsManager to avoid crashes
class SettingsViewModel: ObservableObject {
    @Published var hotkeyModifiers: HotkeyModifiers
    @Published var hotkeyKeyCode: UInt16
    @Published var launchAtLogin: Bool
    @Published var historyLimit: HistoryLimit
    @Published var includePrereleases: Bool
    @Published var hideStatusBar: Bool
    @Published var minTextLength: Int
    @Published var deduplicateHistory: Bool
    @Published var ignoreConcealed: Bool
    @Published var customHistoryLimit: Int
    @Published var autoOCR: Bool
    @Published var preserveRichText: Bool
    @Published var downloadRemoteImages: Bool
    @Published var appTheme: AppTheme
    
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
        if defaults.object(forKey: hotkeyKeyCodeKey) != nil {
            self.hotkeyKeyCode = UInt16(defaults.integer(forKey: hotkeyKeyCodeKey))
        } else {
            self.hotkeyKeyCode = 9
        }
        
        // Load launch at login status from manager natively via SMAppService
        self.launchAtLogin = SettingsManager.shared.launchAtLogin
        
        // Load history limit
        self.historyLimit = SettingsManager.shared.historyLimit
        
        // Load pre-release updates toggle
        self.includePrereleases = defaults.bool(forKey: "includePrereleases")

        // Load hide status bar
        self.hideStatusBar = defaults.bool(forKey: "hideStatusBar")

        // Load clipboard history filtering settings
        self.minTextLength = SettingsManager.shared.minTextLength
        self.deduplicateHistory = SettingsManager.shared.deduplicateHistory
        self.ignoreConcealed = SettingsManager.shared.ignoreConcealed
        self.customHistoryLimit = SettingsManager.shared.customHistoryLimit
        self.autoOCR = SettingsManager.shared.autoOCR
        self.preserveRichText = SettingsManager.shared.preserveRichText
        self.downloadRemoteImages = SettingsManager.shared.downloadRemoteImages

        // Load app theme
        self.appTheme = SettingsManager.shared.appTheme
    }
    
    func save() {
        defaults.set(hotkeyModifiers.toArray(), forKey: hotkeyModifiersKey)
        defaults.set(Int(hotkeyKeyCode), forKey: hotkeyKeyCodeKey)
        defaults.set(historyLimit.rawValue, forKey: "historyLimit")
        defaults.set(includePrereleases, forKey: "includePrereleases")
        defaults.set(hideStatusBar, forKey: "hideStatusBar")
        defaults.set(customHistoryLimit, forKey: "customHistoryLimit")

        SettingsManager.shared.hotkeyModifiers = hotkeyModifiers
        SettingsManager.shared.hotkeyKeyCode = hotkeyKeyCode
        SettingsManager.shared.historyLimit = historyLimit
        SettingsManager.shared.includePrereleases = includePrereleases
        SettingsManager.shared.hideStatusBar = hideStatusBar
        SettingsManager.shared.minTextLength = minTextLength
        SettingsManager.shared.deduplicateHistory = deduplicateHistory
        SettingsManager.shared.ignoreConcealed = ignoreConcealed
        SettingsManager.shared.customHistoryLimit = customHistoryLimit
        SettingsManager.shared.autoOCR = autoOCR
        SettingsManager.shared.preserveRichText = preserveRichText
        SettingsManager.shared.downloadRemoteImages = downloadRemoteImages
        SettingsManager.shared.appTheme = appTheme
        SettingsManager.shared.save()
        SettingsManager.shared.applyTheme(appTheme)

        NotificationCenter.default.post(name: .bufferHotkeyChanged, object: nil)
        NotificationCenter.default.post(name: .bufferHistoryLimitChanged, object: nil)
        NotificationCenter.default.post(name: .bufferStatusBarVisibilityChanged, object: nil)
        NotificationCenter.default.post(name: .bufferThemeChanged, object: nil)
    }
}
