import Foundation
import AppKit

class UpdateService {
    static let shared = UpdateService()
    private init() {}

    private let releasesURL = URL(string: "https://api.github.com/repos/samirpatil2000/release-test/releases")!
    private let lastCheckKey = "lastUpdateCheckDate"
    private let repoBaseURL = "https://github.com/samirpatil2000/Buffer"
    private var progressWindow: NSWindow?
    private var toastWindow: NSWindow?
    private var pendingStarURL: URL?

    func checkOnLaunchIfNeeded() {
        if let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < 86400 {
            let hoursAgo = Date().timeIntervalSince(lastCheck) / 3600
            print("[UpdateService] Skipping launch check — last checked \(String(format: "%.1f", hoursAgo))h ago")
            return
        }
        print("[UpdateService] Running launch check")
        checkForUpdates(silent: true)
    }

    func checkForUpdates(silent: Bool) {
        print("[UpdateService] checkForUpdates(silent: \(silent))")
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                print("[UpdateService] Network error: \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse {
                print("[UpdateService] GitHub API responded: HTTP \(http.statusCode)")
            }
            guard let self,
                  let data,
                  let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                print("[UpdateService] Failed to parse releases JSON")
                return
            }
            print("[UpdateService] Fetched \(releases.count) release(s)")
            self.handleReleases(releases, silent: silent)
        }.resume()
    }

    private func handleReleases(_ releases: [[String: Any]], silent: Bool) {
        let sorted = releases
            .filter { ($0["prerelease"] as? Bool) != true }
            .sorted { (($0["published_at"] as? String) ?? "") > (($1["published_at"] as? String) ?? "") }

        #if arch(arm64)
        let archKeyword = "Silicon"
        #else
        let archKeyword = "Intel"
        #endif

        var latestTag: String?
        var latestZipURL: String?
        for release in sorted {
            guard let tag = release["tag_name"] as? String,
                  let assets = release["assets"] as? [[String: Any]] else { continue }
            let archZip = assets.first(where: {
                guard let name = $0["name"] as? String else { return false }
                return name.hasSuffix(".zip") && name.contains(archKeyword)
            })
            let anyZip = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true })
            if let zip = archZip ?? anyZip,
               let url = zip["browser_download_url"] as? String {
                latestTag = tag
                latestZipURL = url
                print("[UpdateService] Selected asset: \(zip["name"] as? String ?? "?") (\(archKeyword) preferred)")
                break
            }
        }

        guard let tag = latestTag, let zipURL = latestZipURL else {
            print("[UpdateService] No release with a .zip asset found")
            return
        }

        let latest = stripTagPrefix(tag)
        let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        print("[UpdateService] Latest: \(latest)  Current: \(current)  ZipURL: \(zipURL)")

        DispatchQueue.main.async {
            if self.versionIsNewer(latest, than: current) {
                print("[UpdateService] Update available — showing alert")
                self.showUpdateAlert(version: latest, tag: tag, downloadURL: zipURL)
            } else {
                print("[UpdateService] Already up to date (silent: \(silent))")
                if !silent { self.showUpToDateAlert() }
            }
        }
    }

    private func stripTagPrefix(_ tag: String) -> String {
        var v = tag
        let lower = v.lowercased()
        if lower.hasPrefix("buffer-v") {
            v = String(v.dropFirst("buffer-v".count))
        } else if lower.hasPrefix("v") {
            v = String(v.dropFirst(1))
        }
        return v
    }

    private func versionIsNewer(_ latest: String, than current: String) -> Bool {
        let lp = latest.split(separator: ".").compactMap { Int($0) }
        let cp = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(lp.count, cp.count) {
            let l = i < lp.count ? lp[i] : 0
            let c = i < cp.count ? cp[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }

    private func showUpdateAlert(version: String, tag: String, downloadURL: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Buffer \(version) is available"
        alert.informativeText = "A new version of Buffer is ready to download and install."
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        print("[UpdateService] Update alert response: \(response == .alertFirstButtonReturn ? "Update Now" : "Later")")
        if response == .alertFirstButtonReturn {
            downloadAndInstall(url: downloadURL, tag: tag)
        }
    }

    private func showUpToDateAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "You're up to date"
        alert.informativeText = "Buffer is already on the latest version."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func checkIfJustUpdated() {
        guard UserDefaults.standard.bool(forKey: "bufferJustUpdated") else { return }
        UserDefaults.standard.removeObject(forKey: "bufferJustUpdated")
        let tag = UserDefaults.standard.string(forKey: "bufferUpdateTag") ?? ""
        UserDefaults.standard.removeObject(forKey: "bufferUpdateTag")
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        print("[UpdateService] Detected post-update launch, version: \(version), tag: \(tag)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.showSuccessToast(version: version, tag: tag)
        }
    }

    private func showSuccessToast(version: String, tag: String) {
        let w: CGFloat = 270
        let h: CGFloat = 220

        // NSPanel with .nonactivatingPanel never touches app activation state
        // so closing it cannot trigger AppKit's "accessory app with no windows" termination
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        window.alphaValue = 0
        toastWindow = window

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        blur.blendingMode = .behindWindow
        blur.material = .hudWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true
        window.contentView = blur

        // Checkmark icon
        let iconSize: CGFloat = 48
        let iconConfig = NSImage.SymbolConfiguration(pointSize: iconSize * 0.8, weight: .medium)
            .applying(.init(paletteColors: [.white, NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)]))
        let iconView = NSImageView(frame: NSRect(x: (w - iconSize) / 2, y: 154, width: iconSize, height: iconSize))
        iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig)
        blur.addSubview(iconView)

        let title = NSTextField(labelWithString: "Updated Successfully")
        title.font = .boldSystemFont(ofSize: 13)
        title.textColor = .white
        title.alignment = .center
        title.frame = NSRect(x: 0, y: 128, width: w, height: 20)
        blur.addSubview(title)

        let sub = version.isEmpty ? "Buffer is up to date." : "You're now on version \(version)."
        let subtitle = NSTextField(labelWithString: sub)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.55)
        subtitle.alignment = .center
        subtitle.frame = NSRect(x: 0, y: 108, width: w, height: 16)
        blur.addSubview(subtitle)

        let prompt = NSTextField(labelWithString: "Enjoying Buffer? Please ⭐ star the repo!")
        prompt.font = .systemFont(ofSize: 11)
        prompt.textColor = NSColor.white.withAlphaComponent(0.55)
        prompt.alignment = .center
        prompt.frame = NSRect(x: 0, y: 80, width: w, height: 16)
        blur.addSubview(prompt)

        // Star button
        let releaseURLString = tag.isEmpty
            ? repoBaseURL
            : "\(repoBaseURL)/releases/tag/\(tag)"
        pendingStarURL = URL(string: releaseURLString)

        let btn = NSButton(title: "⭐  Star on GitHub", target: self, action: #selector(starButtonTapped))
        btn.bezelStyle = .rounded
        btn.font = .boldSystemFont(ofSize: 12)
        let btnW: CGFloat = 160
        btn.frame = NSRect(x: (w - btnW) / 2, y: 18, width: btnW, height: 30)
        blur.addSubview(btn)

        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 1
        }

        // Auto-dismiss after 8 s (enough time to read and click)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            self.dismissToast()
        }
    }

    @objc private func starButtonTapped() {
        if let url = pendingStarURL {
            NSWorkspace.shared.open(url)
        }
        dismissToast()
    }

    private func dismissToast() {
        guard let window = toastWindow else { return }
        toastWindow = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()
        })
    }

    private func downloadAndInstall(url: String, tag: String) {
        guard let downloadURL = URL(string: url) else {
            print("[UpdateService] Invalid download URL: \(url)")
            return
        }
        print("[UpdateService] Starting download: \(url)")
        showProgressWindow()

        URLSession.shared.downloadTask(with: downloadURL) { [weak self] localURL, _, error in
            guard let self else { return }

            func fail(_ reason: String) {
                print("[UpdateService] \(reason)")
                DispatchQueue.main.async { self.hideProgressWindow() }
            }

            if let error {
                return fail("Download error: \(error.localizedDescription)")
            }
            guard let localURL else {
                return fail("Download returned no file")
            }
            print("[UpdateService] Download complete: \(localURL.path)")

            // 1. UUID-based temp dir — not guessable by other processes
            let fm = FileManager.default
            let tmpBase = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("BufferUpdate_\(UUID().uuidString)")
            let zipURL    = tmpBase.appendingPathComponent("update.zip")
            let extractURL = tmpBase.appendingPathComponent("extracted")
            let newAppURL  = extractURL.appendingPathComponent("Buffer.app")
            let scriptURL  = tmpBase.appendingPathComponent("install.sh")

            do {
                try fm.createDirectory(at: tmpBase, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                try fm.moveItem(at: localURL, to: zipURL)
                print("[UpdateService] Zip at: \(zipURL.path)")
            } catch {
                return fail("Failed to prepare temp dir: \(error)")
            }

            // 2. Extract zip in Swift so we can inspect it before touching /Applications
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-xk", zipURL.path, extractURL.path]
            do {
                try ditto.run(); ditto.waitUntilExit()
                guard ditto.terminationStatus == 0 else {
                    return fail("ditto extraction failed (exit \(ditto.terminationStatus))")
                }
                print("[UpdateService] Extraction OK")
            } catch {
                return fail("Failed to run ditto: \(error)")
            }

            // 3. Confirm Buffer.app is actually present after extraction
            guard fm.fileExists(atPath: newAppURL.path) else {
                return fail("Buffer.app not found in extracted zip at \(newAppURL.path)")
            }

            // 4. Verify code signature before replacing anything
            let codesign = Process()
            codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            codesign.arguments = ["--verify", "--deep", "--strict", newAppURL.path]
            do {
                try codesign.run(); codesign.waitUntilExit()
                guard codesign.terminationStatus == 0 else {
                    return fail("Code signature verification failed (exit \(codesign.terminationStatus))")
                }
                print("[UpdateService] Code signature verified OK")
            } catch {
                return fail("Failed to run codesign: \(error)")
            }

            // 5. Write install script — extraction already done, script only copies + opens
            let script = """
            #!/bin/bash
            sleep 2

            rm -rf "/Applications/Buffer.app"
            if [ $? -ne 0 ]; then
                osascript -e 'display alert "Buffer Update Failed" message "Could not remove old app. Try updating manually."'
                exit 1
            fi

            cp -R "\(newAppURL.path)" "/Applications/Buffer.app"
            if [ $? -ne 0 ]; then
                osascript -e 'display alert "Buffer Update Failed" message "Could not copy new app. Try updating manually."'
                exit 1
            fi

            xattr -cr "/Applications/Buffer.app"
            sleep 1
            /bin/launchctl asuser $(id -u) /usr/bin/open "/Applications/Buffer.app"
            """
            do {
                try script.write(to: scriptURL, atomically: true, encoding: .utf8)
                print("[UpdateService] Install script written to: \(scriptURL.path)")
            } catch {
                return fail("Failed to write install script: \(error)")
            }

            // 6. chmod 755
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["755", scriptURL.path]
            do {
                try chmod.run(); chmod.waitUntilExit()
            } catch {
                return fail("Failed to chmod script: \(error)")
            }

            // 7. Launch script detached via nohup so it survives the app quitting
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
            launcher.arguments = ["-c", "nohup /bin/bash '\(scriptURL.path)' >/dev/null 2>&1 &"]
            do {
                try launcher.run()
                launcher.waitUntilExit() // wait for fork to complete before we exit
                print("[UpdateService] Install script detached, terminating app")
            } catch {
                return fail("Failed to launch install script: \(error)")
            }

            // Pass info to the new app so it can show the success toast
            UserDefaults.standard.set(true, forKey: "bufferJustUpdated")
            UserDefaults.standard.set(tag, forKey: "bufferUpdateTag")
            UserDefaults.standard.set(Date(), forKey: self.lastCheckKey) // suppress launch check in new app
            UserDefaults.standard.synchronize() // flush to disk before process exits

            DispatchQueue.main.async {
                self.hideProgressWindow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }.resume()
    }

    private func showProgressWindow() {
        DispatchQueue.main.async {
            let w: CGFloat = 260
            let h: CGFloat = 168

            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.isReleasedWhenClosed = false
            window.center()

            // Blurred HUD background with rounded corners
            let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            blur.blendingMode = .behindWindow
            blur.material = .hudWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 18
            blur.layer?.masksToBounds = true
            window.contentView = blur

            // App icon
            let iconSize: CGFloat = 52
            let iconView = NSImageView(frame: NSRect(x: (w - iconSize) / 2, y: 100, width: iconSize, height: iconSize))
            iconView.image = NSApp.applicationIconImage
            iconView.imageScaling = .scaleProportionallyDown
            blur.addSubview(iconView)

            // Title
            let title = NSTextField(labelWithString: "Updating Buffer...")
            title.font = .boldSystemFont(ofSize: 13)
            title.textColor = .white
            title.alignment = .center
            title.frame = NSRect(x: 0, y: 72, width: w, height: 20)
            blur.addSubview(title)

            // Subtitle
            let subtitle = NSTextField(labelWithString: "Downloading, please wait...")
            subtitle.font = .systemFont(ofSize: 11)
            subtitle.textColor = NSColor.white.withAlphaComponent(0.55)
            subtitle.alignment = .center
            subtitle.frame = NSRect(x: 0, y: 52, width: w, height: 16)
            blur.addSubview(subtitle)

            // Spinner
            let spinner = NSProgressIndicator(frame: NSRect(x: (w - 20) / 2, y: 20, width: 20, height: 20))
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            blur.addSubview(spinner)

            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.progressWindow = window
            print("[UpdateService] Progress window shown")
        }
    }

    private func hideProgressWindow() {
        DispatchQueue.main.async {
            self.progressWindow?.close()
            self.progressWindow = nil
            print("[UpdateService] Progress window hidden")
        }
    }
}
