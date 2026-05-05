import SwiftUI
import AppKit

/// Single row displaying a clipboard item - optimized for smooth scrolling
struct ClipboardItemRow: View {
    let item: ClipboardItem
    let store: ClipboardStore
    let isMultiSelected: Bool     // True if this item is part of multi-selection
    let joinsSelectionAbove: Bool
    let joinsSelectionBelow: Bool
    let quickPasteNumber: Int?
    
    @State private var isHovered = false
    @State private var thumbnail: NSImage?
    @State private var sourceAppIcon: NSImage?
    @State private var imageDimensionsText: String?
    
    private var backgroundColor: Color {
        if isMultiSelected {
            return Color(nsColor: .selectedContentBackgroundColor)
        } else if isHovered {
            return Color.primary.opacity(0.06)
        }
        return Color.clear
    }

    private var foregroundColor: Color {
        isMultiSelected ? Color(nsColor: .selectedTextColor) : .primary
    }

    private var secondaryForegroundColor: Color {
        isMultiSelected ? Color(nsColor: .selectedTextColor).opacity(0.82) : .secondary
    }

    private var selectionCornerRadius: CGFloat { 6 }
    
    private var primaryLabelText: String {
        switch item.type {
        case .text:
            let text = item.textContent ?? item.previewText
            let singleLine = text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if singleLine.count > 50 {
                return String(singleLine.prefix(50)) + "…"
            }
            return singleLine
        case .image:
            if let imageDimensionsText {
                return "Image (\(imageDimensionsText))"
            }
            return "Image"
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            if let quickPasteNumber {
                quickPasteBadge(quickPasteNumber)
            }

            leadingVisual
                .frame(width: 24, height: 24)
            
            Text(primaryLabelText)
                .font(.system(size: 13))
                .foregroundColor(foregroundColor)
                .lineLimit(1)
            
            Spacer(minLength: 0)

            // Pin indicator
            if item.isPinned {
                Circle()
                    .fill(Color(red: 112/255.0, green: 104/255.0, blue: 196/255.0).opacity(0.7))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(selectionBackground)
        .onHover { hovering in
            isHovered = hovering
        }
        .task(id: item.id) {
            if item.type == .image && thumbnail == nil {
                thumbnail = await loadThumbnail()
                imageDimensionsText = await loadImageDimensionsText()
            }
            if sourceAppIcon == nil {
                sourceAppIcon = await loadSourceApplicationIcon()
            }
        }
    }

    private func quickPasteBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(foregroundColor)
            .frame(width: 20, height: 20)
            .background(
                Circle()
                    .fill(Color.primary.opacity(isMultiSelected ? 0.18 : 0.08))
            )
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(isMultiSelected ? 0.22 : 0.12), lineWidth: 0.5)
            )
    }
    
    @ViewBuilder
    private var leadingVisual: some View {
        switch item.type {
        case .text:
            sourceApplicationVisual
        case .image:
            imageVisual
        }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isMultiSelected {
            ZStack {
                RoundedRectangle(cornerRadius: selectionCornerRadius)
                    .fill(backgroundColor)

                if joinsSelectionAbove {
                    Rectangle()
                        .fill(backgroundColor)
                        .frame(height: selectionCornerRadius)
                        .frame(maxHeight: .infinity, alignment: .top)
                }

                if joinsSelectionBelow {
                    Rectangle()
                        .fill(backgroundColor)
                        .frame(height: selectionCornerRadius)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        } else {
            Rectangle()
                .fill(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder
    private var sourceApplicationVisual: some View {
        if let content = item.textContent?.trimmingCharacters(in: .whitespaces),
           let color = parseColor(content) {
            RoundedRectangle(cornerRadius: 5)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
        } else if let sourceAppIcon {
            Image(nsImage: sourceAppIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .help(item.sourceApp ?? "Source App")
        } else if item.sourceApp != nil || item.sourceAppBundleIdentifier != nil || item.sourceAppBundlePath != nil {
            Image(systemName: "app.fill")
                .font(.system(size: 14))
                .foregroundColor(secondaryForegroundColor)
                .help(item.sourceApp ?? "Source App")
        } else {
            Image(systemName: "doc.text")
                .font(.system(size: 14))
                .foregroundColor(secondaryForegroundColor)
        }
    }

    @ViewBuilder
    private var imageVisual: some View {
        if let img = thumbnail {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipped()
                .cornerRadius(4)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.2))
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

    private func loadImageDimensionsText() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let original = store.image(for: item) else {
                    continuation.resume(returning: nil)
                    return
                }

                if let representation = original.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
                   representation.pixelsWide > 0,
                   representation.pixelsHigh > 0 {
                    continuation.resume(returning: "\(representation.pixelsWide)x\(representation.pixelsHigh)")
                    return
                }

                let width = Int(original.size.width.rounded())
                let height = Int(original.size.height.rounded())
                continuation.resume(returning: width > 0 && height > 0 ? "\(width)x\(height)" : nil)
            }
        }
    }

    private func loadSourceApplicationIcon() async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let iconImage: NSImage?

                if let bundlePath = item.sourceAppBundlePath, !bundlePath.isEmpty {
                    iconImage = NSWorkspace.shared.icon(forFile: bundlePath)
                } else if let bundleIdentifier = item.sourceAppBundleIdentifier,
                          let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                    iconImage = NSWorkspace.shared.icon(forFile: appURL.path)
                } else {
                    iconImage = nil
                }

                guard let iconImage else {
                    continuation.resume(returning: nil)
                    return
                }

                iconImage.size = NSSize(width: 14, height: 14)
                continuation.resume(returning: iconImage)
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
