import Foundation

/// Heuristic, dependency-free language detection for clipboard text.
///
/// Purpose: decide whether a snippet looks like code worth syntax-highlighting, and if so
/// give a best-guess language hint. This runs in FRONT of HighlighterSwift's own highlight.js
/// auto-detection, which is good on idiomatic multi-line code but unreliable on the short
/// fragments and plain prose that dominate a clipboard.
///
/// Design stance: conservative. Most clipboard content is ordinary text, and miscoloring an
/// English paragraph as if it were code is worse than leaving it plain. When there is no
/// strong signal, we return `.plain` and the caller renders unhighlighted text.
///
/// All functions are pure (string in, result out) so they are trivially unit-testable and
/// never touch disk, the network, or app state.
enum LanguageDetector {

    /// The outcome of detection.
    enum Result: Equatable {
        /// Render as plain, unhighlighted text (prose, trivial fragments, or low confidence).
        case plain
        /// Looks like code. The optional hint is a highlight.js language name when we are
        /// reasonably sure; nil means "let highlight.js auto-detect".
        case code(hint: String?)
    }

    /// Minimum length before we even consider highlighting. Shorter than this is almost always
    /// a word, a URL, or a token, not a code block worth coloring.
    private static let minCodeLength = 12

    /// Detect whether `text` should be syntax-highlighted and with which language.
    ///
    /// A caller that already has a user override should NOT call this - the override wins.
    static func detect(_ text: String) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minCodeLength else { return .plain }

        // Strong structural signals first. These are near-certain and cheap.
        if let hint = structuralHint(trimmed) {
            return .code(hint: hint)
        }

        // If it reads like prose, stop here - do not highlight.
        if looksLikeProse(trimmed) {
            return .plain
        }

        // Weaker code signals: punctuation and keyword density typical of source code.
        if looksLikeCode(trimmed) {
            // We believe it is code but are not confident about the language; let the
            // downstream engine auto-detect.
            return .code(hint: nil)
        }

        return .plain
    }

    // MARK: - Strong structural detectors (high confidence, specific language)

    /// Returns a specific language hint when the text has an unambiguous structural marker.
    private static func structuralHint(_ text: String) -> String? {
        // Shebang => shell (covers bash, sh, zsh; highlight.js groups these under "bash").
        if text.hasPrefix("#!") {
            let firstLine = text.prefix { $0 != "\n" }.lowercased()
            if firstLine.contains("python") { return "python" }
            if firstLine.contains("node") { return "javascript" }
            if firstLine.contains("ruby") { return "ruby" }
            return "bash"
        }

        // Unified diff / patch.
        if text.hasPrefix("diff --git") || text.hasPrefix("--- ") && text.contains("\n+++ ") {
            return "diff"
        }

        // JSON: starts with { or [ and parses as JSON.
        if let first = text.first, first == "{" || first == "[" {
            if isValidJSON(text) { return "json" }
        }

        // XML / HTML: starts with a tag or declaration.
        if text.hasPrefix("<?xml") || text.hasPrefix("<!DOCTYPE") { return "xml" }
        if text.hasPrefix("<") && looksLikeMarkup(text) {
            let lower = text.lowercased()
            if lower.contains("<html") || lower.contains("<!doctype html") || lower.contains("<div")
                || lower.contains("<span") || lower.contains("<body") {
                return "xml"  // highlight.js "xml" grammar also covers HTML
            }
            return "xml"
        }

        return nil
    }

    private static func isValidJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    /// Rough check that a `<`-leading string is actually markup (has a matching `>` and a tag name).
    private static func looksLikeMarkup(_ text: String) -> Bool {
        guard let close = text.firstIndex(of: ">") else { return false }
        let tag = text[text.index(after: text.startIndex)..<close]
        guard let firstChar = tag.first else { return false }
        return firstChar.isLetter || firstChar == "!" || firstChar == "/" || firstChar == "?"
    }

    // MARK: - Prose detection (bias toward NOT highlighting)

    /// Heuristic: does this read like natural-language prose rather than code?
    ///
    /// Prose tends to be sentences of words separated by spaces, ending in sentence punctuation,
    /// with very little of the bracket/semicolon/operator punctuation that saturates source code.
    private static func looksLikeProse(_ text: String) -> Bool {
        let codePunctuation = CharacterSet(charactersIn: "{}[]();<>=|&_$`")
        let codePunctCount = text.unicodeScalars.filter { codePunctuation.contains($0) }.count
        let codePunctRatio = Double(codePunctCount) / Double(max(text.count, 1))

        // Lots of code punctuation => not prose.
        if codePunctRatio > 0.03 { return false }

        // Word-like structure: mostly alphabetic words separated by single spaces.
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" })
        guard words.count >= 3 else { return false }

        let alphaWords = words.filter { word in
            word.allSatisfy { $0.isLetter || $0 == "," || $0 == "." || $0 == "'" || $0 == "-" }
        }
        let alphaRatio = Double(alphaWords.count) / Double(words.count)

        // If most tokens are plain words and code punctuation is sparse, treat as prose.
        return alphaRatio > 0.7
    }

    // MARK: - Weak code detectors (lower confidence, no specific language)

    /// Keyword/punctuation density check for "this is probably code, language unknown".
    private static func looksLikeCode(_ text: String) -> Bool {
        // SQL: leading keyword is a strong-enough hint to name the language.
        // Checked here rather than structurally because SQL has no unique opening marker.
        let upperStart = text.uppercased()
        let sqlStarts = ["SELECT ", "INSERT INTO ", "UPDATE ", "DELETE FROM ", "CREATE TABLE ",
                         "ALTER TABLE ", "DROP TABLE ", "WITH "]
        if sqlStarts.contains(where: { upperStart.hasPrefix($0) }) {
            return true
        }

        // YAML: key: value lines, no braces. Checked loosely.
        if looksLikeYAML(text) { return true }

        // Generic code signals: semicolon-terminated lines, braces, common keywords.
        let codeKeywords = ["function ", "const ", "let ", "var ", "def ", "class ", "import ",
                            "return ", "public ", "private ", "func ", "=> ", "#include", "package "]
        let lower = text.lowercased()
        let keywordHits = codeKeywords.filter { lower.contains($0) }.count

        let hasBraces = text.contains("{") && text.contains("}")
        let hasSemicolonLines = text.split(separator: "\n").filter { $0.hasSuffix(";") }.count >= 2

        // Need at least two independent signals to call it code without a specific language.
        let signals = [keywordHits >= 2, hasBraces, hasSemicolonLines].filter { $0 }.count
        return signals >= 1 && keywordHits >= 1 || signals >= 2
    }

    /// Loose YAML detector: several `key: value` lines, no code braces.
    private static func looksLikeYAML(_ text: String) -> Bool {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard lines.count >= 2 else { return false }
        let keyValueLines = lines.filter { line in
            guard let colon = line.firstIndex(of: ":") else { return false }
            // key before colon is a bareword, not a sentence.
            let key = line[line.startIndex..<colon]
            return !key.isEmpty && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        }
        let ratio = Double(keyValueLines.count) / Double(lines.count)
        return ratio > 0.6 && !text.contains("{") && !text.contains(";")
    }
}
