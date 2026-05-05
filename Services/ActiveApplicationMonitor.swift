import AppKit

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
