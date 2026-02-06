import SwiftUI
import AppKit

// -------------------------------------------------------------------------------------
// --------------------------------- Zoom Click Overlay --------------------------------
// -------------------------------------------------------------------------------------

// MARK: - Zoom Click Overlay
// NSView overlay that captures left-click (zoom in) and ctrl+click/right-click (zoom out)
// with appropriate zoom-in/zoom-out cursors

struct ZoomClickOverlay: NSViewRepresentable {
    var onZoomIn: () -> Void
    var onZoomOut: () -> Void

    func makeNSView(context: Context) -> ZoomClickNSView {
        let view = ZoomClickNSView()
        view.onZoomIn = onZoomIn
        view.onZoomOut = onZoomOut
        return view
    }

    func updateNSView(_ nsView: ZoomClickNSView, context: Context) {
        nsView.onZoomIn = onZoomIn
        nsView.onZoomOut = onZoomOut
    }
}

class ZoomClickNSView: NSView {
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var isCtrlHeld = false

    private lazy var zoomInCursor: NSCursor = {
        let size = NSSize(width: 20, height: 20)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setStroke()
            let circle = NSBezierPath(ovalIn: NSRect(x: 2, y: 6, width: 12, height: 12))
            circle.lineWidth = 1.5
            circle.stroke()

            // Plus sign

            let plus = NSBezierPath()
            plus.move(to: NSPoint(x: 8, y: 9))
            plus.line(to: NSPoint(x: 8, y: 15))
            plus.move(to: NSPoint(x: 5, y: 12))
            plus.line(to: NSPoint(x: 11, y: 12))
            plus.lineWidth = 1.5
            plus.stroke()

            // Handle

            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: 12, y: 8))
            handle.line(to: NSPoint(x: 18, y: 2))
            handle.lineWidth = 2
            handle.stroke()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 12))
    }()

    private lazy var zoomOutCursor: NSCursor = {
        let size = NSSize(width: 20, height: 20)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setStroke()
            let circle = NSBezierPath(ovalIn: NSRect(x: 2, y: 6, width: 12, height: 12))
            circle.lineWidth = 1.5
            circle.stroke()

            // Minus sign

            let minus = NSBezierPath()
            minus.move(to: NSPoint(x: 5, y: 12))
            minus.line(to: NSPoint(x: 11, y: 12))
            minus.lineWidth = 1.5
            minus.stroke()

            // Handle

            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: 12, y: 8))
            handle.line(to: NSPoint(x: 18, y: 2))
            handle.lineWidth = 2
            handle.stroke()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 12))
    }()

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(event: event)
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursor(event: event)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func flagsChanged(with event: NSEvent) {
        isCtrlHeld = event.modifierFlags.contains(.control)
        updateCursor(event: event)
    }

    override func mouseDown(with event: NSEvent) {
        onZoomIn?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onZoomOut?()
    }

    private func updateCursor(event: NSEvent) {
        if event.modifierFlags.contains(.control) || isCtrlHeld {
            zoomOutCursor.set()
        } else {
            zoomInCursor.set()
        }
    }
}

// -------------------------------------------------------------------------------------
// --------------------------------- Image Artifact ------------------------------------
// -------------------------------------------------------------------------------------

// MARK: - Image Artifact View

struct ImageArtifactView: View {
    let path: String
    let caption: String
    @State private var image: NSImage?
    @State private var loadFailed = false
    @State private var zoomScale: CGFloat = 0.6

    private let minZoom: CGFloat = 0.2
    private let maxZoom: CGFloat = 3.0
    private let zoomStep: CGFloat = 0.15

    var body: some View {
        VStack(spacing: 0) {
            if let img = image {
                GeometryReader { geo in
                    let imageSize = img.size
                    let fittedWidth = geo.size.width
                    let fittedHeight = geo.size.height
                    let aspectRatio = imageSize.width / imageSize.height

                    // Size that fits the container while preserving aspect ratio

                    let baseWidth = min(fittedWidth, fittedHeight * aspectRatio)
                    let baseHeight = baseWidth / aspectRatio
                    let scaledWidth = baseWidth * zoomScale
                    let scaledHeight = baseHeight * zoomScale

                    let needsScroll = scaledWidth > fittedWidth || scaledHeight > fittedHeight

                    ZStack {
                        if needsScroll {
                            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: scaledWidth, height: scaledHeight)
                                    .frame(minWidth: fittedWidth, minHeight: fittedHeight)
                            }
                        } else {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: scaledWidth, height: scaledHeight)
                                .frame(width: fittedWidth, height: fittedHeight)
                        }

                        // Transparent click overlay for zoom handling + cursor

                        ZoomClickOverlay(
                            onZoomIn: {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    zoomScale = min(zoomScale + zoomStep, maxZoom)
                                }
                            },
                            onZoomOut: {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    zoomScale = max(zoomScale - zoomStep, minZoom)
                                }
                            }
                        )
                        .frame(width: fittedWidth, height: fittedHeight)
                    }
                }
                .background(Color.black)

                // Zoom indicator

                HStack(spacing: 6) {
                    Text("\(Int(zoomScale * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)

                    Button(action: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            zoomScale = max(zoomScale - zoomStep, minZoom)
                        }
                    }) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            zoomScale = min(zoomScale + zoomStep, maxZoom)
                        }
                    }) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            zoomScale = 0.6
                        }
                    }) {
                        Text("Reset")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(Color(white: 0.06))
            } else if loadFailed {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)

                    Text("Image not found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))

                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.05))
            } else {
                VStack {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("Loading image...")
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }

            // Caption

            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.08))
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        guard !path.isEmpty else {
            loadFailed = true
            return
        }

        if let img = NSImage(contentsOfFile: path) {
            image = img
        } else {
            loadFailed = true
        }
    }
}
