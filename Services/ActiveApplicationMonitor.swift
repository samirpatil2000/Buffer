import AppKit

struct SourceApplicationInfo {
    let name: String?
    let bundleIdentifier: String?
    let bundlePath: String?
}

final class ActiveApplicationMonitor {
    static let shared = ActiveApplicationMonitor()

    private(set) var currentApplication: NSRunningApplication?

    private init(notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    var currentApplicationName: String? {
        currentApplication?.localizedName
    }

    var currentApplicationInfo: SourceApplicationInfo {
        SourceApplicationInfo(
            name: currentApplication?.localizedName,
            bundleIdentifier: currentApplication?.bundleIdentifier,
            bundlePath: currentApplication?.bundleURL?.path
        )
    }

    @objc
    private func handleAppActivation(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        guard application.processIdentifier != currentProcessID else {
            return
        }

        currentApplication = application
    }
}
