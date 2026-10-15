import Foundation
import UniformTypeIdentifiers

/// Intelligent syntax and file extension detector for clipboard text
struct SyntaxDetector {
    
    struct DetectionResult {
        let fileExtension: String
        let contentType: UTType
        let suggestedFileName: String
    }
    
    /// Detect language, file extension, and appropriate UTType from text snippet
    static func detect(text: String) -> DetectionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return defaultTextResult()
        }
        
        let sample = String(trimmed.prefix(4000))
        let lines = sample.components(separatedBy: .newlines)
        let firstLine = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
        
        // 1. Shebang detection (top priority)
        if firstLine.hasPrefix("#!") {
            let lower = firstLine.lowercased()
            if lower.contains("bash") || lower.contains("/sh") || lower.contains("zsh") {
                return makeResult(ext: "sh", type: .shellScript, prefix: "Script", lines: lines)
            } else if lower.contains("python") {
                return makeResult(ext: "py", type: .pythonScript, prefix: "Script", lines: lines)
            } else if lower.contains("node") || lower.contains("deno") || lower.contains("bun") {
                return makeResult(ext: "js", type: UTType(filenameExtension: "js") ?? .plainText, prefix: "Script", lines: lines)
            } else if lower.contains("ruby") {
                return makeResult(ext: "rb", type: UTType(filenameExtension: "rb") ?? .plainText, prefix: "Script", lines: lines)
            } else if lower.contains("perl") {
                return makeResult(ext: "pl", type: UTType(filenameExtension: "pl") ?? .plainText, prefix: "Script", lines: lines)
            }
        }
        
        // 2. Structured formats
        // JSON
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            if isValidJSON(trimmed) {
                return makeResult(ext: "json", type: .json, prefix: "Data", lines: lines)
            }
        }
        
        // HTML
        let lowerTrimmed = trimmed.lowercased()
        if lowerTrimmed.hasPrefix("<!doctype html") || lowerTrimmed.hasPrefix("<html") {
            return makeResult(ext: "html", type: .html, prefix: "Page", lines: lines)
        }
        
        // SVG
        if lowerTrimmed.hasPrefix("<svg") || (lowerTrimmed.hasPrefix("<?xml") && lowerTrimmed.contains("<svg")) {
            return makeResult(ext: "svg", type: .svg, prefix: "Graphic", lines: lines)
        }
        
        // XML
        if lowerTrimmed.hasPrefix("<?xml") {
            return makeResult(ext: "xml", type: .xml, prefix: "Document", lines: lines)
        }
        
        // 3. Git diff & terminal build logs
        if trimmed.hasPrefix("diff --git") || trimmed.hasPrefix("--- a/") || (sample.contains("@@ -") && sample.contains("@@ +")) {
            return makeResult(ext: "diff", type: UTType(filenameExtension: "diff") ?? .plainText, prefix: "Changes", lines: lines)
        }
        
        if isBuildOrGitLog(sample: sample, lines: lines) {
            return makeResult(ext: "log", type: UTType(filenameExtension: "log") ?? .plainText, prefix: "Log", lines: lines)
        }
        
        // 4. SQL
        if isSQL(sample: sample, firstLine: firstLine) {
            return makeResult(ext: "sql", type: UTType(filenameExtension: "sql") ?? .plainText, prefix: "Query", lines: lines)
        }
        
        // 5. YAML
        if trimmed.hasPrefix("---") && (sample.contains(":\n") || sample.contains(": ")) {
            return makeResult(ext: "yaml", type: UTType(filenameExtension: "yaml") ?? .plainText, prefix: "Config", lines: lines)
        }
        
        // 6. Markdown
        if isMarkdown(sample: sample, lines: lines) {
            return makeResult(ext: "md", type: UTType(filenameExtension: "md") ?? .plainText, prefix: "Note", lines: lines)
        }
        
        // 7. Source code heuristics
        // Swift
        if sample.contains("import SwiftUI") || sample.contains("import Foundation") || sample.contains("import AppKit") || (sample.contains("func ") && sample.contains("var ") && sample.contains("-> ")) {
            return makeResult(ext: "swift", type: .swiftSource, prefix: "Snippet", lines: lines)
        }
        
        // Python
        if (sample.contains("def ") && sample.contains(":")) || sample.contains("import os") || sample.contains("if __name__ == '__main__':") || sample.contains("if __name__ == \"__main__\":") {
            return makeResult(ext: "py", type: .pythonScript, prefix: "Snippet", lines: lines)
        }
        
        // CSS / SCSS
        if sample.contains("{") && sample.contains("}") && (sample.contains("display:") || sample.contains("color:") || sample.contains("margin:") || sample.contains("padding:")) {
            return makeResult(ext: "css", type: UTType(filenameExtension: "css") ?? .plainText, prefix: "Styles", lines: lines)
        }
        
        // Rust
        if (sample.contains("fn ") && sample.contains("let mut ")) || sample.contains("pub struct ") || sample.contains("impl ") {
            return makeResult(ext: "rs", type: UTType(filenameExtension: "rs") ?? .plainText, prefix: "Snippet", lines: lines)
        }
        
        // Fallback: Plain Text
        return makeResult(ext: "txt", type: .plainText, prefix: "Snippet", lines: lines)
    }
    
    // MARK: - Helper Methods
    
    private static func defaultTextResult() -> DetectionResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        return DetectionResult(fileExtension: "txt", contentType: .plainText, suggestedFileName: "Snippet-\(timestamp).txt")
    }
    
    private static func isValidJSON(_ string: String) -> Bool {
        // Fast limit for JSON serialization check
        let testString = string.count > 500_000 ? String(string.prefix(500_000)) : string
        guard let data = testString.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
    
    private static func isBuildOrGitLog(sample: String, lines: [String]) -> Bool {
        let indicators = [
            "Fast-forward",
            "files changed,",
            "insertions(+)",
            "deletions(-)",
            "git pull",
            "git status",
            "origin/main",
            "origin/master",
            "Building target",
            "ninja:",
            "Scanning dependencies",
            "[ 0%]",
            "[100%]",
            "error: ",
            "warning: ",
            "cmake",
            "CMake"
        ]
        var matchCount = 0
        for indicator in indicators {
            if sample.contains(indicator) {
                matchCount += 1
                if matchCount >= 2 { return true }
            }
        }
        return false
    }
    
    private static func isSQL(sample: String, firstLine: String) -> Bool {
        let upperFirst = firstLine.uppercased()
        let sqlKeywords = ["SELECT ", "INSERT INTO ", "UPDATE ", "DELETE FROM ", "CREATE TABLE ", "ALTER TABLE ", "DROP TABLE ", "CREATE INDEX "]
        for keyword in sqlKeywords {
            if upperFirst.hasPrefix(keyword) { return true }
        }
        return false
    }
    
    private static func isMarkdown(sample: String, lines: [String]) -> Bool {
        if lines.first?.trimmingCharacters(in: .whitespaces).hasPrefix("# ") == true { return true }
        if sample.contains("```") && (sample.contains("## ") || sample.contains("- [ ]") || sample.contains("- [x]")) {
            return true
        }
        return false
    }
    
    private static func makeResult(ext: String, type: UTType, prefix: String, lines: [String]) -> DetectionResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        
        // Try to derive meaningful title from first line if it's markdown or comment
        if let first = lines.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty {
            var candidate = first
            if candidate.hasPrefix("# ") {
                candidate = String(candidate.dropFirst(2))
            } else if candidate.hasPrefix("// ") {
                candidate = String(candidate.dropFirst(3))
            } else if candidate.hasPrefix("/* ") && candidate.hasSuffix(" */") {
                candidate = String(candidate.dropFirst(3).dropLast(3))
            }
            
            candidate = candidate.trimmingCharacters(in: .whitespaces)
            let sanitized = candidate
                .components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:;"))
                .joined(separator: "-")
                .trimmingCharacters(in: .whitespaces)
            
            // If sanitized candidate is reasonably short and readable, use it
            if sanitized.count >= 3 && sanitized.count <= 35 && !sanitized.contains("{") && !sanitized.contains("=") {
                return DetectionResult(
                    fileExtension: ext,
                    contentType: type,
                    suggestedFileName: "\(sanitized).\(ext)"
                )
            }
        }
        
        return DetectionResult(
            fileExtension: ext,
            contentType: type,
            suggestedFileName: "\(prefix)-\(timestamp).\(ext)"
        )
    }
}
