import SwiftUI

/// Single row displaying a clipboard item - cleaner design with hover
struct ClipboardItemRow: View {
    let item: ClipboardItem
    let store: ClipboardStore
    let isSelected: Bool
    
    @State private var isHovered = false
    
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
                .frame(width: 20)
            
            // Content preview
            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewText)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if item.type == .image, let filename = item.imageFilename {
                    Text(filename)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer(minLength: 0)
            
            // Source app badge
            if let app = item.sourceApp {
                Text(app)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .cornerRadius(6)
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .animation(.easeOut(duration: 0.1), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    @ViewBuilder
    private var icon: some View {
        switch item.type {
        case .text:
            Image(systemName: "doc.text")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        case .image:
            if let nsImage = store.image(for: item) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 20, height: 20)
                    .cornerRadius(3)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
    }
}
