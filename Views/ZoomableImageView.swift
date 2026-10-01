import SwiftUI
import AppKit

/// Native AppKit NSView that handles image drawing, direct manipulation zooming, and panning.
/// Crucially sets `mouseDownCanMoveWindow = false` so mouse dragging on the image never moves the window.
final class ZoomableImageNSView: NSView {
    var image: NSImage?
    var scale: CGFloat = 1.0
    var panOffset: CGPoint = .zero
    
    static let minScale: CGFloat = 1.0
    static let maxScale: CGFloat = 4.0
    static let defaultDoubleTapScale: CGFloat = 2.5
    
    private var isDragging = false
    private var trackingArea: NSTrackingArea?
    private var animationTimer: Timer?
    
    // Critical: Prevents window movement when dragging the image
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let img = image, bounds.width > 0, bounds.height > 0 else { return }
        
        let baseW = bounds.width
        let baseH = bounds.height
        let drawW = baseW * scale
        let drawH = baseH * scale
        
        let maxPanX = max(0, (baseW * (scale - 1.0)) / 2.0)
        let maxPanY = max(0, (baseH * (scale - 1.0)) / 2.0)
        let clampedX = min(max(panOffset.x, -maxPanX), maxPanX)
        let clampedY = min(max(panOffset.y, -maxPanY), maxPanY)
        
        let centerX = (baseW / 2.0) + clampedX
        let centerY = (baseH / 2.0) + clampedY
        
        let drawRect = NSRect(
            x: centerX - (drawW / 2.0),
            y: centerY - (drawH / 2.0),
            width: drawW,
            height: drawH
        )
        
        NSGraphicsContext.current?.imageInterpolation = .high
        let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
        path.addClip()
        img.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
    
    // MARK: - Mouse & Touch Handling
    
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            handleDoubleTap()
            return
        }
        if scale > 1.01 {
            isDragging = true
            NSCursor.closedHand.set()
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard scale > 1.01 else { return }
        panOffset.x += event.deltaX
        panOffset.y -= event.deltaY
        clampPan()
        needsDisplay = true
        NSCursor.closedHand.set()
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        updateCursor()
    }
    
    override func scrollWheel(with event: NSEvent) {
        if scale > 1.01 {
            panOffset.x += event.scrollingDeltaX
            panOffset.y -= event.scrollingDeltaY
            clampPan()
            needsDisplay = true
        } else {
            // Forward scroll event to parent SwiftUI ScrollView so list/text scrolling works
            nextResponder?.scrollWheel(with: event)
        }
    }
    
    override func magnify(with event: NSEvent) {
        let newScale = min(max(scale * (1.0 + event.magnification), Self.minScale), Self.maxScale)
        scale = newScale
        clampPan()
        needsDisplay = true
        updateCursor()
    }
    
    override func mouseEntered(with event: NSEvent) {
        updateCursor()
    }
    
    override func mouseMoved(with event: NSEvent) {
        updateCursor()
    }
    
    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }
    
    // MARK: - Internal Helpers
    
    func clampPan() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let maxPanX = max(0, (bounds.width * (scale - 1.0)) / 2.0)
        let maxPanY = max(0, (bounds.height * (scale - 1.0)) / 2.0)
        panOffset.x = min(max(panOffset.x, -maxPanX), maxPanX)
        panOffset.y = min(max(panOffset.y, -maxPanY), maxPanY)
    }
    
    private func updateCursor() {
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
    
    private func handleDoubleTap() {
        if scale > 1.05 {
            animateTo(targetScale: Self.minScale, targetOffset: .zero)
        } else {
            let targetScale = calculateDoubleTapScale()
            animateTo(targetScale: targetScale, targetOffset: .zero)
        }
    }
    
    private func calculateDoubleTapScale() -> CGFloat {
        guard let img = image, bounds.width > 0, img.size.width > 0 else {
            return Self.defaultDoubleTapScale
        }
        let nativeRatio = img.size.width / bounds.width
        if nativeRatio > 1.2 {
            return min(max(nativeRatio, 1.8), Self.maxScale)
        }
        return Self.defaultDoubleTapScale
    }
    
    private func animateTo(targetScale: CGFloat, targetOffset: CGPoint) {
        let startScale = self.scale
        let startOffset = self.panOffset
        let duration: TimeInterval = 0.2
        let startTime = CACurrentMediaTime()
        
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(CGFloat(elapsed / duration), 1.0)
            // Ease out quad
            let t = 1.0 - pow(1.0 - progress, 2.0)
            
            self.scale = startScale + (targetScale - startScale) * t
            self.panOffset = CGPoint(
                x: startOffset.x + (targetOffset.x - startOffset.x) * t,
                y: startOffset.y + (targetOffset.y - startOffset.y) * t
            )
            self.clampPan()
            self.needsDisplay = true
            
            if progress >= 1.0 {
                timer.invalidate()
                self.animationTimer = nil
                self.updateCursor()
            }
        }
    }
}

/// SwiftUI wrapper for ZoomableImageNSView
struct ZoomableImageRepresentable: NSViewRepresentable {
    let image: NSImage
    
    func makeNSView(context: Context) -> ZoomableImageNSView {
        let view = ZoomableImageNSView()
        view.image = image
        return view
    }
    
    func updateNSView(_ nsView: ZoomableImageNSView, context: Context) {
        if nsView.image !== image {
            nsView.image = image
            nsView.scale = ZoomableImageNSView.minScale
            nsView.panOffset = .zero
            nsView.needsDisplay = true
        }
    }
}

/// Interactive, zoomable image preview component.
/// Supports trackpad pinch-to-zoom, drag-to-pan when magnified,
/// and double-click toggle between 100% actual size and fit.
struct ZoomableImageView: View {
    let image: NSImage
    
    static let minScale: CGFloat = ZoomableImageNSView.minScale
    static let maxScale: CGFloat = ZoomableImageNSView.maxScale
    static let defaultDoubleTapScale: CGFloat = ZoomableImageNSView.defaultDoubleTapScale
    
    private var aspectRatio: CGFloat {
        guard image.size.width > 0, image.size.height > 0 else { return 4.0 / 3.0 }
        return image.size.width / image.size.height
    }
    
    var body: some View {
        ZoomableImageRepresentable(image: image)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .help("Double-click to toggle 100% actual size • Pinch to zoom • Drag to pan")
    }
}
