import Foundation
import AppKit

// https://opensource.apple.com/source/CarbonLibs/CarbonLib-6771/CommonHeaders/Appearance.h.auto.html
private let errAEEventNotPermitted = -1743

/// Resolves a `SourceContext` for whatever app was frontmost when the clipboard
/// changed. Browser context (domain + truncated page title) is captured via
/// AppleScript for a small allowlist of supported browsers; everything else
/// falls back to plain app name. All lookups are best-effort and local-only.
final class SourceResolver {
    static let shared = SourceResolver()

    /// Maximum number of characters we keep from a page title.
    private let maxTitleLength = 120

    /// Compiled scripts cached per script source string identity (browser name primary, id fallback secondary).
    private var scriptCache: [String: NSAppleScript] = [:]
    private let cacheQueue = DispatchQueue(label: "com.buffer.sourceresolver.cache")

    /// Avoid spamming Console on every clipboard poll for the same failure.
    private var loggedAppleScriptSignatures = Set<String>()
    private let logQueue = DispatchQueue(label: "com.buffer.sourceresolver.log")

    /// Prefer name-based targeting; maps bundle IDs to the exact scripting name on disk.
    private let browserNames: [String: String] = [
        "com.apple.Safari": "Safari",
        "com.google.Chrome": "Google Chrome",
        "com.google.Chrome.canary": "Google Chrome Canary",
        "com.google.Chrome.beta": "Google Chrome Beta",
        "com.google.Chrome.dev": "Google Chrome Dev",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.microsoft.edgemac.Beta": "Microsoft Edge Beta",
        "com.microsoft.edgemac.Dev": "Microsoft Edge Dev",
        "com.microsoft.edgemac.Canary": "Microsoft Edge Canary",
        "com.brave.Browser": "Brave Browser",
        "com.brave.Browser.beta": "Brave Browser Beta",
        "com.brave.Browser.nightly": "Brave Browser Nightly",
        "company.thebrowser.Browser": "Arc",
        "org.chromium.Chromium": "Chromium"
    ]

    private let chromiumFamilyBundleIDs: Set<String> = Set([
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "company.thebrowser.Browser",
        "org.chromium.Chromium"
    ])

    private let safariBundleID = "com.apple.Safari"

    private init() {}

    /// Resolve source context for the current frontmost application.
    func resolveCurrentSource() -> SourceContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appName = app.localizedName
        let bundleID = app.bundleIdentifier

        if let bundleID = bundleID,
           let browserInfo = resolveBrowserContext(bundleID: bundleID) {
            return SourceContext(
                appName: appName,
                appBundleID: bundleID,
                domain: browserInfo.domain,
                pageTitle: browserInfo.title
            )
        }

        return SourceContext(appName: appName, appBundleID: bundleID)
    }

    // MARK: - Browser lookup

    private func resolveBrowserContext(bundleID: String) -> (domain: String?, title: String?)? {
        guard let scriptingName = browserNames[bundleID] else { return nil }

        let raw: String?
        if bundleID == safariBundleID {
            raw = runSafari(byName: scriptingName)
        } else if chromiumFamilyBundleIDs.contains(bundleID) {
            raw = runChromium(byName: scriptingName, bundleID: bundleID)
        } else {
            return nil
        }

        guard let raw = raw, !raw.isEmpty else { return nil }

        let parts = raw.components(separatedBy: "\u{1F}")
        let urlString = parts.first ?? ""
        let title = parts.count > 1 ? parts[1] : ""

        let domain = normalizedHost(from: urlString)
        let truncatedTitle = truncate(title)

        if domain == nil && (truncatedTitle?.isEmpty ?? true) {
            return nil
        }
        return (domain, truncatedTitle)
    }

    // MARK: - Script execution

    private func runSafari(byName name: String) -> String? {
        let scriptPrimary = safariScript(applicationName: name)
        let keyPrimary = "safari:name:\(name)"
        if let s = runScript(scriptPrimary, cacheKey: keyPrimary, diagnosticLabel: "\(keyPrimary) Safari") {
            return s
        }
        let scriptFallback = safariScript(byBundleID: safariBundleID)
        let keyFallback = "safari:id:\(safariBundleID)"
        return runScript(scriptFallback, cacheKey: keyFallback, diagnosticLabel: keyFallback)
    }

    private func runChromium(byName name: String, bundleID: String) -> String? {
        let scriptPrimary = chromiumScript(applicationName: name)
        let keyPrimary = "chromium:name:\(name)"
        if let s = runScript(scriptPrimary, cacheKey: keyPrimary, diagnosticLabel: "\(keyPrimary) chromium") {
            return s
        }
        let scriptFallback = chromiumScript(byBundleID: bundleID)
        let keyFallback = "chromium:id:\(bundleID)"
        return runScript(scriptFallback, cacheKey: keyFallback, diagnosticLabel: keyFallback)
    }

    private func runScript(_ source: String, cacheKey key: String, diagnosticLabel: String) -> String? {
        let script: NSAppleScript? = cacheQueue.sync {
            if let cached = scriptCache[key] { return cached }
            guard let compiled = NSAppleScript(source: source) else {
                print("[Buffer] AppleScript compile failed for \(diagnosticLabel)")
                return nil
            }
            scriptCache[key] = compiled
            return compiled
        }
        guard let appleScript = script else { return nil }

        var errorInfo: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else {
            logAppleScriptError(diagnosticLabel: diagnosticLabel, errorInfo: errorInfo)
            return nil
        }
        return descriptor.stringValue
    }

    private func logAppleScriptError(diagnosticLabel: String, errorInfo: NSDictionary?) {
        let number = (errorInfo?["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue ?? 0
        let message = (errorInfo?["NSAppleScriptErrorMessage"] as? String) ?? "unknown"
        let signature = "\(diagnosticLabel)|\(number)|\(message)"
        let shouldLog = logQueue.sync {
            if loggedAppleScriptSignatures.contains(signature) { return false }
            loggedAppleScriptSignatures.insert(signature)
            return true
        }
        guard shouldLog else { return }

        print("[Buffer] AppleScript error for \(diagnosticLabel): \(number) \(message)")
        if number == errAEEventNotPermitted {
            if let bid = Bundle.main.bundleIdentifier {
                print("[Buffer] Automation blocked. Grant Buffer access in System Settings > Privacy & Security > Automation (or reset: tccutil reset AppleEvents \(bid))")
            }
        }
    }

    // MARK: - Scripts (no inner try/on error — we need errors in Swift/TCC path)

    private func safariScript(applicationName name: String) -> String {
        let escaped = escapeForAppleScriptStringLiteral(name)
        return """
            tell application "\(escaped)"
                set theTab to current tab of front window
                set theURL to URL of theTab
                set theTitle to name of theTab
                return (theURL as text) & (ASCII character 31) & (theTitle as text)
            end tell
            """
    }

    private func safariScript(byBundleID bundleID: String) -> String {
        let escaped = escapeForAppleScriptStringLiteral(bundleID)
        return """
            tell application id "\(escaped)"
                set theTab to current tab of front window
                set theURL to URL of theTab
                set theTitle to name of theTab
                return (theURL as text) & (ASCII character 31) & (theTitle as text)
            end tell
            """
    }

    private func chromiumScript(applicationName name: String) -> String {
        let escaped = escapeForAppleScriptStringLiteral(name)
        return """
            tell application "\(escaped)"
                set theTab to active tab of front window
                set theURL to URL of theTab
                set theTitle to title of theTab
                return (theURL as text) & (ASCII character 31) & (theTitle as text)
            end tell
            """
    }

    private func chromiumScript(byBundleID bundleID: String) -> String {
        let escaped = escapeForAppleScriptStringLiteral(bundleID)
        return """
            tell application id "\(escaped)"
                set theTab to active tab of front window
                set theURL to URL of theTab
                set theTitle to title of theTab
                return (theURL as text) & (ASCII character 31) & (theTitle as text)
            end tell
            """
    }

    private func escapeForAppleScriptStringLiteral(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - URL / title helpers

    private func normalizedHost(from urlString: String) -> String? {
        guard !urlString.isEmpty else { return nil }
        guard let components = URLComponents(string: urlString),
              var host = components.host,
              !host.isEmpty else { return nil }
        if host.lowercased().hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        return host
    }

    private func truncate(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= maxTitleLength { return trimmed }
        return String(trimmed.prefix(maxTitleLength)) + "…"
    }
}
