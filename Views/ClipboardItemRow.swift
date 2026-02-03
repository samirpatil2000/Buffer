import SwiftUI

/// Single row displaying a clipboard item - optimized for smooth scrolling
struct ClipboardItemRow: View {
    let item: ClipboardItem
    let store: ClipboardStore
    let isSelected: Bool
    
    @State private var isHovered = false
    @State private var thumbnail: NSImage?
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.25)
        } else if isHovered {
            return Color.primary.opacity(0.06)
        }
        return Color.clear
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            icon
                .frame(width: 20, height: 20)
            
            // Content preview - simplified
            Text(item.previewText)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer(minLength: 0)
            
            // Source app badge
            if let app = item.sourceApp {
                Text(app)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
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
}
