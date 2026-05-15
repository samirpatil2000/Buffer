import AppKit
import SwiftUI

// MARK: - Layout metrics (single source of truth)

enum AppFilterPopoverMetrics {
    /// Narrower panel; labels hug the trailing switches instead of stretching across a wide chip.
    static let popoverWidth: CGFloat = 276
    static let rowHeight: CGFloat = 64
    /// Inner top/bottom padding for the translucent shell (taller silhouette).
    static let shellVerticalPadding: CGFloat = 10
    static let horizontalPadding: CGFloat = 14
    /// Fixed column so every row’s icon aligns; app artwork is centered inside.
    static let iconColumnWidth: CGFloat = 34
    /// Rounded app icons in rows.
    static let appIconSize: CGFloat = 26
    /// System symbol for header row.
    static let headerSymbolPointSize: CGFloat = 17
    static let columnSpacing: CGFloat = 8
    /// Slightly tighter than before; `.fixedSize()` on the toggle still sizes the control intrinsically.
    static let toggleColumnWidth: CGFloat = 42
    static let shellCornerRadius: CGFloat = 14
    static let rowHighlightCornerRadius: CGFloat = 10
    static let shellShadowRadius: CGFloat = 18
    static let shellShadowYOffset: CGFloat = 8
    static let shellShadowOpacityDark: CGFloat = 0.28
    static let shellShadowOpacityLight: CGFloat = 0.14
    /// Taller scroll area so more rows are visible without feeling horizontally stretched.
    static let scrollMaxHeight: CGFloat = 420
    static let rowHoverHorizontalInset: CGFloat = 8
    static let labelFontSize: CGFloat = 13
    static let headerLabelFontSize: CGFloat = 13
}

// MARK: - Header row (“All apps”)

struct HeaderToggleRow: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: AppFilterPopoverMetrics.columnSpacing) {
            Image(systemName: "square.grid.2x2")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: AppFilterPopoverMetrics.headerSymbolPointSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: AppFilterPopoverMetrics.iconColumnWidth, height: AppFilterPopoverMetrics.appIconSize, alignment: .center)
                .contentShape(Rectangle())

            Text("All apps")
                .font(.system(size: AppFilterPopoverMetrics.headerLabelFontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
                .fixedSize()
                .frame(width: AppFilterPopoverMetrics.toggleColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, AppFilterPopoverMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, minHeight: AppFilterPopoverMetrics.rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("All apps")
    }
}

// MARK: - App row with hover highlight

struct AppToggleRow: View {
    let appName: String
    let bundleID: String?
    @Binding var isOn: Bool

    @Environment(\.colorScheme) private var colorScheme

    @State private var isHovered = false

    private var appIconImage: NSImage? {
        AppIconCache.shared.icon(for: bundleID)
    }

    var body: some View {
        ZStack(alignment: .center) {
            if isHovered {
                RoundedRectangle(cornerRadius: AppFilterPopoverMetrics.rowHighlightCornerRadius, style: .continuous)
                    .fill((colorScheme == .dark ? Color.white : Color.black).opacity(colorScheme == .dark ? 0.08 : 0.055))
                    .padding(.horizontal, AppFilterPopoverMetrics.rowHoverHorizontalInset)
            }

            HStack(alignment: .center, spacing: AppFilterPopoverMetrics.columnSpacing) {
                iconView
                    .frame(width: AppFilterPopoverMetrics.iconColumnWidth, alignment: .center)

                Text(appName)
                    .font(.system(size: AppFilterPopoverMetrics.labelFontSize))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                    .fixedSize()
                    .frame(width: AppFilterPopoverMetrics.toggleColumnWidth, alignment: .trailing)
            }
            .padding(.horizontal, AppFilterPopoverMetrics.horizontalPadding)
        }
        .frame(maxWidth: .infinity, minHeight: AppFilterPopoverMetrics.rowHeight)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(appName)
    }

    @ViewBuilder
    private var iconView: some View {
        if let img = appIconImage {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: AppFilterPopoverMetrics.appIconSize, height: AppFilterPopoverMetrics.appIconSize)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: AppFilterPopoverMetrics.appIconSize, height: AppFilterPopoverMetrics.appIconSize)
        }
    }
}

// MARK: - Chrome shell

struct AppFilterPopoverShell<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content()
            .frame(width: AppFilterPopoverMetrics.popoverWidth)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: AppFilterPopoverMetrics.shellCornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: AppFilterPopoverMetrics.shellCornerRadius, style: .continuous)
                        .strokeBorder(separatorTint, lineWidth: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppFilterPopoverMetrics.shellCornerRadius, style: .continuous))
            .shadow(
                color: .black.opacity(colorScheme == .dark ? AppFilterPopoverMetrics.shellShadowOpacityDark : AppFilterPopoverMetrics.shellShadowOpacityLight),
                radius: AppFilterPopoverMetrics.shellShadowRadius,
                x: 0,
                y: AppFilterPopoverMetrics.shellShadowYOffset
            )
    }

    private var separatorTint: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10)
    }
}
