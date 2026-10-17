import Foundation

/// Dependency-free pretty-printer for the formats Foundation can handle natively.
///
/// This does NOT depend on the syntax highlighter (highlight.js only colors text, it never
/// rewrites it). Formatting is a separate capability, deliberately limited to JSON and XML/HTML
/// because those are the only languages Foundation can reflow without bundling external tools.
enum CodeFormatter {

    /// Languages this formatter can pretty-print. Used to decide whether to show the button.
    /// Values are highlight.js language names as produced by LanguageDetector / the picker.
    static func canFormat(language: String?, text: String) -> Bool {
        switch resolve(language: language, text: text) {
        case .json, .xml: return true
        case .none: return false
        }
    }

    /// Pretty-print `text` for the given language, or nil if it cannot be formatted (unsupported
    /// language, or the content does not actually parse). A nil return means "leave it alone".
    static func format(_ text: String, language: String?) -> String? {
        switch resolve(language: language, text: text) {
        case .json: return formatJSON(text)
        case .xml: return formatXML(text)
        case .none: return nil
        }
    }

    /// Collapse `text` to its most compact single-line form for the given language, or nil if it
    /// cannot be minified. The inverse of `format`, so the UI button can toggle between the two.
    static func minify(_ text: String, language: String?) -> String? {
        switch resolve(language: language, text: text) {
        case .json: return minifyJSON(text)
        case .xml: return minifyXML(text)
        case .none: return nil
        }
    }

    /// Whether `text` already appears pretty-printed (multi-line with indentation), so the UI can
    /// decide whether the next toggle action should minify (true) or pretty-print (false).
    /// Conservative: only reports true for formattable content that contains a newline.
    static func isPretty(language: String?, text: String) -> Bool {
        switch resolve(language: language, text: text) {
        case .json, .xml:
            return text.contains("\n")
        case .none:
            return false
        }
    }

    // MARK: - Private

    private enum Formattable {
        case json
        case xml
        case none
    }

    /// Decide which formatter applies, honoring an explicit language when given and otherwise
    /// sniffing the content. Kept conservative: only commit to a formatter when the content
    /// plausibly matches, so the button never appears for text we would fail to format.
    private static func resolve(language: String?, text: String) -> Formattable {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        if let language = language, !language.isEmpty {
            switch language.lowercased() {
            case "json": return trimmed.first == "{" || trimmed.first == "[" ? .json : .none
            case "xml", "html": return trimmed.first == "<" ? .xml : .none
            default: return .none
            }
        }

        // No explicit language: sniff.
        if trimmed.first == "{" || trimmed.first == "[" {
            return isValidJSON(trimmed) ? .json : .none
        }
        if trimmed.first == "<" {
            return .xml
        }
        return .none
    }

    private static func isValidJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func formatJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        // .sortedKeys is intentionally omitted so the original key order is preserved.
        guard let pretty = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        ) else {
            return nil
        }
        return String(decoding: pretty, as: UTF8.self)
    }

    private static func formatXML(_ text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        // nodePrettyPrint reflows with indentation. Preserve whitespace so content is not lost.
        let options: XMLNode.Options = [.nodePrettyPrint, .documentTidyXML]
        guard let doc = try? XMLDocument(data: data, options: options) else {
            return nil
        }
        let out = doc.xmlData(options: [.nodePrettyPrint])
        let formatted = String(decoding: out, as: UTF8.self)
        return formatted.isEmpty ? nil : formatted
    }

    private static func minifyJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        // No .prettyPrinted option gives the compact single-line form. Preserve key order and
        // keep slashes unescaped so the round trip matches the pretty-printer.
        guard let compact = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.withoutEscapingSlashes]
        ) else {
            return nil
        }
        return String(decoding: compact, as: UTF8.self)
    }

    private static func minifyXML(_ text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        // Parse with pretty-print off and tidy on, then emit without pretty-print so inter-element
        // whitespace is dropped. documentTidyXML drops the ignorable whitespace between nodes.
        guard let doc = try? XMLDocument(data: data, options: [.documentTidyXML]) else {
            return nil
        }
        let out = doc.xmlData()
        let compact = String(decoding: out, as: UTF8.self)
        return compact.isEmpty ? nil : compact
    }
}
