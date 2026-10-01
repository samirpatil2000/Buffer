import SwiftUI
import AppKit

/// Preference key used to read the rendered container size of the image view
private struct ZoomImageSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

/// Interactive, zoomable image preview component.
/// Supports trackpad pinch-to-zoom, drag-to-pan when magnified,
/// double-click toggle between 100% actual size and fit,
/// and external scale synchronization (e.g. ⌘+/⌘-/⌘0).
struct ZoomableImageView: View {
    let image: NSImage
    @Binding var scale: CGFloat
    var onScaleChanged: ((CGFloat) -> Void)? = nil
    
    // Bounds
    static let minScale: CGFloat = 1.0
    static let maxScale: CGFloat = 4.0
    static let defaultDoubleTapScale: CGFloat = 2.5
    
    // Internal pan & drag state
    @State private var panOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var isHovered: Bool = false
    @State private var containerSize: CGSize = .zero
    
    @GestureState private var pinchMagnification: CGFloat = 1.0
    
    private var displayScale: CGFloat {
        min(max(scale * pinchMagnification, Self.minScale), Self.maxScale)
    }
    
    var body: some View {
        let currentEffectiveScale = displayScale
        let effectiveOffset = clampedOffset(panOffset, scale: currentEffectiveScale, containerSize: containerSize)
        
        withPanGesture(
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(currentEffectiveScale)
                    .offset(effectiveOffset)
            }
            .frame(maxWidth: .infinity)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ZoomImageSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(ZoomImageSizePreferenceKey.self) { size in
                containerSize = size
            }
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(magnificationGesture)
            .onTapGesture(count: 2) {
                handleDoubleTap()
            }
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    updateCursor()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .help("Double-click to toggle 100% actual size • Pinch to zoom • Drag to pan"),
            containerSize: containerSize
        )
        .onChange(of: scale) { newScale in
            if newScale <= 1.01 {
                panOffset = .zero
                dragStartOffset = .zero
            } else {
                panOffset = clampedOffset(panOffset, scale: newScale, containerSize: containerSize)
                dragStartOffset = panOffset
            }
            updateCursor()
        }
        .onChange(of: image) { _ in
            scale = Self.minScale
            panOffset = .zero
            dragStartOffset = .zero
            updateCursor()
        }
    }
    
    // MARK: - Gestures
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchMagnification) { value, state, _ in
                state = value
            }
            .onEnded { value in
                let target = min(max(scale * value, Self.minScale), Self.maxScale)
                withAnimation(.easeOut(duration: 0.15)) {
                    scale = target
                    panOffset = clampedOffset(panOffset, scale: target, containerSize: containerSize)
                    dragStartOffset = panOffset
                }
                onScaleChanged?(target)
                updateCursor()
            }
    }
    
    @ViewBuilder
    private func withPanGesture<Content: View>(_ content: Content, containerSize: CGSize) -> some View {
        if scale > 1.01 {
            content.gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        isDragging = true
                        let proposed = CGSize(
                            width: dragStartOffset.width + value.translation.width,
                            height: dragStartOffset.height + value.translation.height
                        )
                        panOffset = clampedOffset(proposed, scale: scale, containerSize: containerSize)
                        updateCursor()
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragStartOffset = panOffset
                        updateCursor()
                    }
            )
        } else {
            content
        }
    }
    
    // MARK: - Actions
    
    private func handleDoubleTap() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            if scale > 1.05 {
                scale = Self.minScale
                panOffset = .zero
                dragStartOffset = .zero
                onScaleChanged?(Self.minScale)
            } else {
                let target = calculateDoubleTapScale()
                scale = target
                onScaleChanged?(target)
            }
        }
        updateCursor()
    }
    
    private func calculateDoubleTapScale() -> CGFloat {
        guard containerSize.width > 0, image.size.width > 0 else {
            return Self.defaultDoubleTapScale
        }
        let nativeRatio = image.size.width / containerSize.width
        if nativeRatio > 1.2 {
            return min(max(nativeRatio, 1.8), Self.maxScale)
        }
        return Self.defaultDoubleTapScale
    }
    
    private func clampedOffset(_ offset: CGSize, scale: CGFloat, containerSize: CGSize) -> CGSize {
        guard scale > 1.0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let maxPanX = (containerSize.width * (scale - 1.0)) / 2.0
        let maxPanY = (containerSize.height * (scale - 1.0)) / 2.0
        let clampedX = min(max(offset.width, -maxPanX), maxPanX)
        let clampedY = min(max(offset.height, -maxPanY), maxPanY)
        return CGSize(width: clampedX, height: clampedY)
    }
    
    private func updateCursor() {
        guard isHovered else { return }
        if scale > 1.01 {
            if isDragging {
                NSCursor.closedHand.set()
            } else {
                NSCursor.openHand.set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }
}
