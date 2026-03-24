import AppKit
import QuartzCore

/// NSView subclass that hosts a CAMetalLayer for libghostty's Metal renderer.
///
/// libghostty renders directly into the Metal layer — this view's job is to:
/// 1. Provide a CAMetalLayer as its backing layer
/// 2. Forward keyboard, mouse, and scroll events to GhosttyBridge
/// 3. Notify GhosttyBridge on resize
///
/// Reference: Ghostty's SurfaceView_AppKit.swift
class TerminalSurface: NSView {
    weak var bridge: GhosttyBridge?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer = CAMetalLayer()

        // Metal layer configuration
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.device = MTLCreateSystemDefaultDevice()
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.framebufferOnly = true
            metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.drawableSize = convertToBacking(newSize)
        }
        bridge?.surfaceDidResize(self)
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        bridge?.sendKeyEvent(event, to: self)
    }

    override func keyUp(with event: NSEvent) {
        bridge?.sendKeyEvent(event, to: self)
    }

    override func flagsChanged(with event: NSEvent) {
        bridge?.sendKeyEvent(event, to: self)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        bridge?.sendMouseEvent(event, to: self)
    }

    override func mouseUp(with event: NSEvent) {
        bridge?.sendMouseEvent(event, to: self)
    }

    override func mouseDragged(with event: NSEvent) {
        bridge?.sendMouseEvent(event, to: self)
    }

    override func mouseMoved(with event: NSEvent) {
        bridge?.sendMouseEvent(event, to: self)
    }

    override func rightMouseDown(with event: NSEvent) {
        bridge?.sendMouseEvent(event, to: self)
    }

    override func rightMouseUp(with event: NSEvent) {
        bridge?.sendMouseEvent(event, to: self)
    }

    // MARK: - Scroll Events

    override func scrollWheel(with event: NSEvent) {
        bridge?.sendScrollEvent(event, to: self)
    }
}
