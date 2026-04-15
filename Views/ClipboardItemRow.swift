import SwiftUI

/// Single row displaying a clipboard item - optimized for smooth scrolling
struct ClipboardItemRow: View {
    let item: ClipboardItem
    let store: ClipboardStore
    let isPrimarySelection: Bool  // True for focused row (full accent), false otherwise
    let isMultiSelected: Bool     // True if this item is part of multi-selection
    
    @State private var isHovered = false
    @State private var thumbnail: NSImage?
    
    private var backgroundColor: Color {
        if isMultiSelected && !isPrimarySelection {
            // Multi-selected item: distinct purple highlight
            return Color.purple.opacity(0.15)
        } else if isPrimarySelection {
            // Single selection: blue highlight (original behavior)
            return Color.accentColor.opacity(0.25)
        } else if isHovered {
            return Color.primary.opacity(0.06)
        }
        return Color.clear
    }
    
    /// Truncated preview for list display - short and single line
    private var truncatedPreviewText: String {
        let text = item.textContent ?? item.previewText
        // Replace newlines and extra whitespace with single space
        let singleLine = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        // Truncate to 50 characters for compact display
        if singleLine.count > 50 {
            return String(singleLine.prefix(50)) + "…"
        }
        return singleLine
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            icon
                .frame(width: 20, height: 20)
            
            // Content preview - truncated for list view
            Text(truncatedPreviewText)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer(minLength: 0)
            
            // Bookmark indicator
            if item.isBookmarked {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 10))
            }
            
            // Source app badge
            if let app = item.sourceApp {
                Text(app)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // Pin indicator
            if item.isPinned {
                Circle()
                    .fill(Color(red: 112/255.0, green: 104/255.0, blue: 196/255.0).opacity(0.7))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
        }
        .task(id: item.id) {
            // Load thumbnail async off main thread
            if item.type == .image && thumbnail == nil {
                thumbnail = await loadThumbnail()
            }
        }
    }
    
    @ViewBuilder
    private var icon: some View {
        // Check if text content is a pure color value
        if item.type == .text,
           let content = item.textContent?.trimmingCharacters(in: .whitespaces),
           let color = parseColor(content) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 20, height: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
        } else {
            switch item.type {
            case .text:
                Image(systemName: "doc.text")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            case .image:
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 20, height: 20)
                        .clipped()
                        .cornerRadius(2)
                } else {
                    // Placeholder while loading
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 20, height: 20)
                }
            }
        }
    }
    
    /// Generate a small thumbnail asynchronously
    private func loadThumbnail() async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let original = store.image(for: item) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Create a tiny thumbnail (40x40 for retina)
                let thumbSize = NSSize(width: 40, height: 40)
                let thumb = NSImage(size: thumbSize)
                thumb.lockFocus()
                original.draw(
                    in: NSRect(origin: .zero, size: thumbSize),
                    from: NSRect(origin: .zero, size: original.size),
                    operation: .copy,
                    fraction: 1.0
                )
                thumb.unlockFocus()
                
                continuation.resume(returning: thumb)
            }
        }
    }
    
    /// Parse a CSS color value from a string
    /// Supports: #RGB, #RRGGBB, #RRGGBBAA, rgb(...), rgba(...), hsl(...), hsla(...)
    /// Returns nil if the string doesn't match exactly one of these formats
    private func parseColor(_ string: String) -> Color? {
        let trimmed = string.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        
        // Try hex formats
        if trimmed.hasPrefix("#") {
            let hexStr = String(trimmed.dropFirst())
            if let color = parseHex(hexStr) {
                return color
            }
        }
        
        // Try rgb/rgba formats
        if trimmed.hasPrefix("rgb") {
            if let color = parseRGB(trimmed) {
                return color
            }
        }
        
        // Try hsl/hsla formats
        if trimmed.hasPrefix("hsl") {
            if let color = parseHSL(trimmed) {
                return color
            }
        }
        
        return nil
    }
    
    /// Parse hex color (#RGB, #RRGGBB, or #RRGGBBAA)
    private func parseHex(_ hexStr: String) -> Color? {
        let hex = hexStr.filter { $0.isHexDigit }
        
        if hex.count == 3 {
            // Expand #RGB to #RRGGBB
            let expanded = hex.map { "\($0)\($0)" }.joined()
            return parseHex6(expanded)
        } else if hex.count == 6 {
            return parseHex6(hex)
        } else if hex.count == 8 {
            return parseHex8(hex)
        }
        
        return nil
    }
    
    /// Parse 6-digit hex color to RGB
    private func parseHex6(_ hex: String) -> Color? {
        guard let value = UInt64(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
    
    /// Parse 8-digit hex color to RGBA
    private func parseHex8(_ hex: String) -> Color? {
        guard let value = UInt64(hex, radix: 16) else { return nil }
        let r = Double((value >> 24) & 0xFF) / 255.0
        let g = Double((value >> 16) & 0xFF) / 255.0
        let b = Double((value >> 8) & 0xFF) / 255.0
        let a = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b, opacity: a)
    }
    
    /// Parse rgb(...) or rgba(...) format
    private func parseRGB(_ string: String) -> Color? {
        let isRGBA = string.hasPrefix("rgba")
        let startOffset = isRGBA ? 5 : 4
        
        guard string.count > startOffset + 1 else { return nil }
        guard string.hasSuffix(")") else { return nil }
        
        let startIdx = string.index(string.startIndex, offsetBy: startOffset)
        let endIdx = string.index(string.endIndex, offsetBy: -1)
        let content = String(string[startIdx..<endIdx]).trimmingCharacters(in: .whitespaces)
        
        let components = content.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        guard components.count >= 3 else { return nil }
        guard let r = Double(components[0]).map({ $0 / 255.0 }),
              let g = Double(components[1]).map({ $0 / 255.0 }),
              let b = Double(components[2]).map({ $0 / 255.0 }) else { return nil }
        
        let a = isRGBA && components.count >= 4 ? Double(components[3]) ?? 1.0 : 1.0
        
        return Color(red: r, green: g, blue: b, opacity: a)
    }
    
    /// Parse hsl(...) or hsla(...) format
    private func parseHSL(_ string: String) -> Color? {
        let isHSLA = string.hasPrefix("hsla")
        let startOffset = isHSLA ? 5 : 4
        
        guard string.count > startOffset + 1 else { return nil }
        guard string.hasSuffix(")") else { return nil }
        
        let startIdx = string.index(string.startIndex, offsetBy: startOffset)
        let endIdx = string.index(string.endIndex, offsetBy: -1)
        let content = String(string[startIdx..<endIdx]).trimmingCharacters(in: .whitespaces)
        
        let components = content.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        guard components.count >= 3 else { return nil }
        
        // Parse H (0-360), S (0-100%), L (0-100%)
        guard let h = Double(components[0].filter { $0.isNumber || $0 == "-" || $0 == "." }),
              let s = Double(components[1].filter { $0.isNumber || $0 == "." }),
              let l = Double(components[2].filter { $0.isNumber || $0 == "." }) else { return nil }
        
        let a = isHSLA && components.count >= 4 ? Double(components[3]) ?? 1.0 : 1.0
        
        let (r, g, b) = hslToRGB(h: h, s: s / 100.0, l: l / 100.0)
        
        return Color(red: r, green: g, blue: b, opacity: a)
    }
    
    /// Convert HSL to RGB using standard algorithm
    private func hslToRGB(h: Double, s: Double, l: Double) -> (Double, Double, Double) {
        let h = h.truncatingRemainder(dividingBy: 360)
        let s = max(0, min(1, s))
        let l = max(0, min(1, l))
        
        if s == 0 {
            return (l, l, l)
        }
        
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        
        func hueToRGB(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1/6 { return p + (q - p) * 6 * t }
            if t < 1/2 { return q }
            if t < 2/3 { return p + (q - p) * (2/3 - t) * 6 }
            return p
        }
        
        let hNorm = h / 360
        let r = hueToRGB(p, q, hNorm + 1/3)
        let g = hueToRGB(p, q, hNorm)
        let b = hueToRGB(p, q, hNorm - 1/3)
        
        return (r, g, b)
    }
}
