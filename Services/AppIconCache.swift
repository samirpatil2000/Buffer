import AppKit

/// Lightweight in-memory cache for application icons keyed by bundle identifier.
final class AppIconCache {
    static let shared = AppIconCache()

    private var icons: [String: NSImage] = [:]
    private let queue = DispatchQueue(label: "com.buffer.appiconcache")

    private init() {}

    func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID = bundleID, !bundleID.isEmpty else { return nil }

        var cached: NSImage?
        queue.sync {
            cached = icons[bundleID]
        }
        if cached != nil { return cached }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let fetched = NSWorkspace.shared.icon(forFile: url.path)
        // Never cache the workspace icon instance directly — mutating `.size` is global state
        // and breaks SwiftUI/AppKit when the same image is reused across rows.
        let imageToStore: NSImage = (fetched.copy() as? NSImage) ?? fetched
        // Raster size for crisp display at ~27–28 pt (@2x / @3x).
        imageToStore.size = NSSize(width: 36, height: 36)

        queue.sync {
            icons[bundleID] = imageToStore
        }
        return imageToStore
    }
}
