import SwiftUI
import AppKit

enum BufferTheme: String, CaseIterable {
    case system
    case midnight
    case sage
    case sunset
    case monochrome

    var name: String {
        switch self {
        case .system:     return "System"
        case .midnight:   return "Midnight"
        case .sage:       return "Sage"
        case .sunset:     return "Sunset"
        case .monochrome: return "Mono"
        }
    }

    var accentColor: Color {
        switch self {
        case .system:     return Color.accentColor
        case .midnight:   return Color(NSColor.systemIndigo)
        case .sage:       return Color(NSColor.systemGreen)
        case .sunset:     return Color(NSColor.systemOrange)
        case .monochrome: return Color(NSColor.systemGray)
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .midnight: return NSAppearance(named: .darkAqua)
        default:        return nil  // follows system
        }
    }
}

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var current: BufferTheme

    private init() {
        let saved = UserDefaults.standard.string(forKey: "bufferTheme") ?? ""
        self.current = BufferTheme(rawValue: saved) ?? .system
        applyAppearance(current)
    }

    func apply(_ theme: BufferTheme) {
        current = theme
        applyAppearance(theme)
        UserDefaults.standard.set(theme.rawValue, forKey: "bufferTheme")
    }

    private func applyAppearance(_ theme: BufferTheme) {
        NSApp.appearance = theme.appearance
    }
}
