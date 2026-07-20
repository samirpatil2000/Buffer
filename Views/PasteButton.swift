import SwiftUI

/// A modular, reusable Paste button component displaying both the Paste icon,
/// the Return shortcut icon, and the "Paste" label.
struct PasteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 11, weight: .medium))
                
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .medium))
                
                Text("Paste")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.85))
            )
            .foregroundColor(Color(NSColor.windowBackgroundColor))
        }
        .buttonStyle(.plain)
    }
}
