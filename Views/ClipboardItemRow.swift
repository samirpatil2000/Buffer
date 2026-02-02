import SwiftUI

/// Single row displaying a clipboard item - optimized for smooth scrolling
struct ClipboardItemRow: View {
    let item: ClipboardItem
    let store: ClipboardStore
    let isSelected: Bool
    
    @State private var isHovered = false
    @State private var cachedImage: NSImage?
    
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
        .animation(.linear(duration: 0.08), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            // Load image once on appear
            if item.type == .image && cachedImage == nil {
                cachedImage = store.image(for: item)
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
            if let img = cachedImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 20, height: 20)
                    .clipped()
                    .cornerRadius(2)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }
}
