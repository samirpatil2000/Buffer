import Foundation
import AppKit

class UpdateService {
    static let shared = UpdateService()
    private init() {}

    private let releasesURL = URL(string: "https://api.github.com/repos/samirpatil2000/Buffer/releases")!
    private let lastCheckKey = "lastUpdateCheckDate"
    private var progressWindow: NSWindow?

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
            // .filter { ($0["prerelease"] as? Bool) != true }
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
                self.showUpdateAlert(version: latest, downloadURL: zipURL)
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

    private func showUpdateAlert(version: String, downloadURL: String) {
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
            downloadAndInstall(url: downloadURL)
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

    private func downloadAndInstall(url: String) {
        guard let downloadURL = URL(string: url) else {
            print("[UpdateService] Invalid download URL: \(url)")
            return
        }
        print("[UpdateService] Starting download: \(url)")
        showProgressWindow()

        URLSession.shared.downloadTask(with: downloadURL) { [weak self] localURL, _, error in
            guard let self else { return }
            if let error {
                print("[UpdateService] Download error: \(error.localizedDescription)")
                DispatchQueue.main.async { self.hideProgressWindow() }
                return
            }
            guard let localURL else {
                print("[UpdateService] Download returned no file")
                DispatchQueue.main.async { self.hideProgressWindow() }
                return
            }
            print("[UpdateService] Download complete: \(localURL.path)")

            let tmp = NSTemporaryDirectory()
            let zipPath = tmp + "BufferUpdate.zip"
            let extractDir = tmp + "BufferUpdateExtracted"
            let scriptPath = tmp + "buffer_update.sh"

            try? FileManager.default.removeItem(atPath: zipPath)
            try? FileManager.default.moveItem(at: localURL, to: URL(fileURLWithPath: zipPath))
            print("[UpdateService] Zip moved to: \(zipPath)")

            let script = """
            #!/bin/bash
            sleep 1.5
            rm -rf "\(extractDir)"
            mkdir -p "\(extractDir)"
            ditto -xk "\(zipPath)" "\(extractDir)"
            rm -rf "/Applications/Buffer.app"
            cp -R "\(extractDir)/Buffer.app" "/Applications/Buffer.app"
            open "/Applications/Buffer.app"
            """
            try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            print("[UpdateService] Install script written to: \(scriptPath)")

            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["755", scriptPath]
            try? chmod.run()
            chmod.waitUntilExit()

            print("[UpdateService] Launching install script and terminating app")
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
            launcher.arguments = [scriptPath]
            try? launcher.run()

            DispatchQueue.main.async {
                self.hideProgressWindow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }.resume()
    }

    private func showProgressWindow() {
        DispatchQueue.main.async {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 220, height: 80),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.title = "Updating Buffer..."
            window.center()

            let spinner = NSProgressIndicator(frame: NSRect(x: 90, y: 20, width: 40, height: 40))
            spinner.style = .spinning
            spinner.startAnimation(nil)
            window.contentView?.addSubview(spinner)

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
