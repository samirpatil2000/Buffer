import Foundation
import ServiceManagement
import Combine

/// Define the tiers as a type
enum HistoryLimit: Int, CaseIterable, Codable {
    case essential  = 100
    case deep       = 500
    case unlimited  = 1000
    
    var label: String {
        switch self {
        case .essential: return "Essential"
        case .deep:      return "Deep"
        case .unlimited: return "Unlimited"
        }
    }
    
    var subtitle: String {
        switch self {
        case .essential: return "100 items"
        case .deep:      return "500 items"
        case .unlimited: return "1,000 items"
        }
    }
}

/// Manages user preferences for Buffer
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    // Keys
    private let hotkeyModifiersKey = "hotkeyModifiers"
    private let hotkeyKeyCodeKey = "hotkeyKeyCode"
    private let minTextLengthKey = "minTextLength"
    private let deduplicateHistoryKey = "deduplicateHistory"
    private let contentZoomScaleKey = "contentZoomScale"

    static let zoomLevels: [Double] = [0.8, 0.9, 1.0, 1.15, 1.3, 1.5]
    static let defaultZoomScale: Double = 1.0
    static let minZoomScale: Double = 0.8
    static let maxZoomScale: Double = 1.5
    
    @Published var hotkeyModifiers: HotkeyModifiers
    @Published var hotkeyKeyCode: UInt16
    @Published var launchAtLogin: Bool = false
    @Published var historyLimit: HistoryLimit = .essential
    @Published var includePrereleases: Bool = false
    @Published var hideStatusBar: Bool = false
    @Published var minTextLength: Int = 1
    @Published var deduplicateHistory: Bool = false
    @Published var contentZoomScale: Double = defaultZoomScale
    @Published var selectedSettingsTab: Int = 0
    
    private init() {
        // Initialize with defaults first, then load saved values
        let defaultMods = HotkeyModifiers(shift: true, command: true, option: false, control: false)
        let defaultKeyCode: UInt16 = 9  // V key
        
        // Load saved modifiers or use default
        if let savedMods = defaults.array(forKey: hotkeyModifiersKey) as? [String] {
            self.hotkeyModifiers = HotkeyModifiers(from: savedMods)
        } else {
            self.hotkeyModifiers = defaultMods
        }
        
        // Load saved keycode or use default (V key)
        let savedKeyCode = defaults.integer(forKey: hotkeyKeyCodeKey)
        self.hotkeyKeyCode = savedKeyCode > 0 ? UInt16(savedKeyCode) : defaultKeyCode
        
        // Load launch at login status
        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        
        // Load history limit
        let rawLimit = defaults.integer(forKey: "historyLimit")
        self.historyLimit = HistoryLimit(rawValue: rawLimit) ?? .essential
        
        // Load pre-release updates toggle
        self.includePrereleases = defaults.bool(forKey: "includePrereleases")

        // Load hide status bar
        self.hideStatusBar = defaults.bool(forKey: "hideStatusBar")

        // Load clipboard history filtering settings
        self.minTextLength = defaults.object(forKey: minTextLengthKey) as? Int ?? 1
        self.deduplicateHistory = defaults.bool(forKey: deduplicateHistoryKey)

        // Load content zoom scale
        let savedZoom = defaults.double(forKey: contentZoomScaleKey)
        if savedZoom >= Self.minZoomScale && savedZoom <= Self.maxZoomScale {
            self.contentZoomScale = savedZoom
        } else {
            self.contentZoomScale = Self.defaultZoomScale
        }
    }
    
    func save() {
        defaults.set(hotkeyModifiers.toArray(), forKey: hotkeyModifiersKey)
        defaults.set(Int(hotkeyKeyCode), forKey: hotkeyKeyCodeKey)
        defaults.set(historyLimit.rawValue, forKey: "historyLimit")
        defaults.set(includePrereleases, forKey: "includePrereleases")
        defaults.set(hideStatusBar, forKey: "hideStatusBar")
        defaults.set(minTextLength, forKey: minTextLengthKey)
        defaults.set(deduplicateHistory, forKey: deduplicateHistoryKey)
        defaults.set(contentZoomScale, forKey: contentZoomScaleKey)
    }

    func zoomIn() {
        let current = contentZoomScale
        if let next = Self.zoomLevels.first(where: { $0 > current + 0.01 }) {
            contentZoomScale = next
        } else {
            contentZoomScale = Self.maxZoomScale
        }
        save()
    }

    func zoomOut() {
        let current = contentZoomScale
        if let prev = Self.zoomLevels.last(where: { $0 < current - 0.01 }) {
            contentZoomScale = prev
        } else {
            contentZoomScale = Self.minZoomScale
        }
        save()
    }

    func zoomReset() {
        contentZoomScale = Self.defaultZoomScale
        save()
    }
    
    func toggleLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status == .enabled { return }
                    try SMAppService.mainApp.register()
                } else {
                    if SMAppService.mainApp.status == .notRegistered { return }
                    try SMAppService.mainApp.unregister()
                }
                self.launchAtLogin = enabled
            } catch {
                print("Failed to toggle Launch at Login: \(error.localizedDescription)")
                // Revert state if it fails
                self.launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

/// Represents hotkey modifier keys
struct HotkeyModifiers: Equatable {
    var shift: Bool
    var command: Bool
    var option: Bool
    var control: Bool
    
    init(shift: Bool = false, command: Bool = false, option: Bool = false, control: Bool = false) {
        self.shift = shift
        self.command = command
        self.option = option
        self.control = control
    }
    
    init(from array: [String]) {
        self.shift = array.contains("shift")
        self.command = array.contains("command")
        self.option = array.contains("option")
        self.control = array.contains("control")
    }
    
    func toArray() -> [String] {
        var result: [String] = []
        if shift { result.append("shift") }
        if command { result.append("command") }
        if option { result.append("option") }
        if control { result.append("control") }
        return result
    }
    
    var displayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        return parts.joined()
    }
}

/// Map key codes to display names
let keyCodeNames: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
    8: "C", 9: "V", 10: "§", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
    16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
    24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
    32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K",
    41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
    49: "Space", 50: "`"
]
