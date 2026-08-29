import Cocoa

/// Captures a region of the screen, runs on-device OCR on it, and places the
/// recognized text on the clipboard — the image itself never touches the clipboard.
///
/// Uses the system `screencapture` tool for region selection so the familiar
/// macOS crosshair UI (and its Esc-to-cancel behaviour) comes for free.
@MainActor
final class ScreenCaptureService {
    static let shared = ScreenCaptureService()

    private var isCapturing = false

    private init() {}

    /// Entry point for the Capture to Text hotkey
    func captureTextToClipboard() {
        guard !isCapturing else {
            print("[Buffer Capture] Capture already in progress")
            return
        }

        guard ensureScreenRecordingPermission() else { return }

        isCapturing = true

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("buffer-capture-\(UUID().uuidString).png")

        Task {
            defer {
                isCapturing = false
                try? FileManager.default.removeItem(at: url)
            }

            // User pressed Esc or the capture failed — stay silent, this is a normal cancel
            guard await runScreenCapture(to: url) else { return }

            guard let image = NSImage(contentsOf: url) else {
                CaptureHUD.shared.show("Capture failed", symbol: "exclamationmark.triangle")
                return
            }

            let recognized = await OCRService.shared.recognizeText(from: image)
            let text = recognized?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if text.isEmpty {
                handleNoTextFound(image: image)
            } else {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                // ClipboardWatcher picks this up on its next poll and files it in history
                CaptureHUD.shared.show("Text copied", symbol: "text.viewfinder")
            }
        }
    }

    private func handleNoTextFound(image: NSImage) {
        if SettingsManager.shared.captureFallbackToImage {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
            CaptureHUD.shared.show("No text — image copied", symbol: "photo")
        } else {
            CaptureHUD.shared.show("No text found", symbol: "text.viewfinder")
        }
    }

    /// Runs the interactive region capture. Returns false when the user cancels.
    private func runScreenCapture(to url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                // -i interactive region, -x no camera sound, -o no window shadow
                process.arguments = ["-i", "-x", "-o", url.path]

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    print("[Buffer Capture] Failed to launch screencapture: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                    return
                }

                // Esc leaves a non-zero status and no file behind
                let succeeded = process.terminationStatus == 0
                    && FileManager.default.fileExists(atPath: url.path)
                continuation.resume(returning: succeeded)
            }
        }
    }

    // MARK: - Permissions

    /// Screen Recording is a separate TCC grant from Accessibility, and it is only
    /// ever requested when the user actually triggers a capture.
    private func ensureScreenRecordingPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }

        CGRequestScreenCaptureAccess()

        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = "Capture to Text reads the region you select, so macOS requires Screen Recording access for Buffer.\n\nEnable it in System Settings › Privacy & Security › Screen Recording, then try again."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }

        return false
    }
}

/// Small transient HUD used to confirm a capture without stealing focus from
/// the app the user is about to paste into.
@MainActor
private final class CaptureHUD {
    static let shared = CaptureHUD()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String, symbol: String, duration: TimeInterval = 1.4) {
        dismissTask?.cancel()
        panel?.orderOut(nil)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        icon.contentTintColor = .labelColor

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 18)

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true

        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])

        let size = stack.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = effect
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + 120
            ))
        }

        // orderFrontRegardless keeps the frontmost app active so ⌘V works immediately
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }

            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0.25
            panel.animator().alphaValue = 0
            NSAnimationContext.endGrouping()

            try? await Task.sleep(nanoseconds: 300_000_000)
            panel.orderOut(nil)
            if self?.panel === panel { self?.panel = nil }
        }
    }
}
