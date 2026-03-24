import AppKit
import GhosttyKit
import QuartzCore

/// NSView subclass that hosts a terminal surface backed by libghostty's Metal renderer.
///
/// Each instance owns a `ghostty_surface_t` and forwards input events directly.
class TerminalSurface: NSView {
    private(set) var surface: ghostty_surface_t?
    private var previousModifierFlags: NSEvent.ModifierFlags = []

    /// Called when libghostty requests this surface be closed.
    var onClose: (() -> Void)?

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
        // libghostty manages the CAMetalLayer internally via the NSView pointer.
        // We just need to ensure the view is layer-backed.
    }

    // MARK: - Surface Lifecycle

    func createSurface(app: ghostty_app_t) {
        // Guard against double-creation (e.g. tab switch re-attach)
        guard self.surface == nil else { return }

        var cfg = ghostty_surface_config_new()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform.macos.nsview = Unmanaged.passUnretained(self).toOpaque()
        cfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        cfg.scale_factor = Double(window?.screen?.backingScaleFactor
                                  ?? NSScreen.main?.backingScaleFactor ?? 1.0)
        cfg.font_size = 0  // inherit from config
        cfg.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        self.surface = ghostty_surface_new(app, &cfg)
        if self.surface == nil {
            print("[TerminalSurface] ghostty_surface_new() failed")
        }
    }

    func destroySurface() {
        if let surface {
            ghostty_surface_free(surface)
            self.surface = nil
        }
    }

    deinit {
        destroySurface()
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if let surface {
            ghostty_surface_set_focus(surface, true)
        }
        return true
    }

    override func resignFirstResponder() -> Bool {
        if let surface {
            ghostty_surface_set_focus(surface, false)
        }
        return true
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface else { return }

        let scale = window?.screen?.backingScaleFactor
                    ?? NSScreen.main?.backingScaleFactor ?? 2.0
        ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))
        let backed = convertToBacking(newSize)
        ghostty_surface_set_size(surface, UInt32(backed.width), UInt32(backed.height))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let surface, let screen = window?.screen else { return }
        let scale = screen.backingScaleFactor
        ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        guard let surface else { return }

        let mods = Self.ghosttyMods(from: event.modifierFlags)
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyEvent.mods = mods
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.composing = false

        // Provide the text for character input
        if let chars = event.characters, !chars.isEmpty {
            chars.withCString { cStr in
                keyEvent.text = cStr
                _ = ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.text = nil
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else { return }

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_RELEASE
        keyEvent.mods = Self.ghosttyMods(from: event.modifierFlags)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.text = nil
        keyEvent.composing = false

        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else { return }

        // Detect press vs release by comparing current flags to previous state.
        let current = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let previous = previousModifierFlags
        previousModifierFlags = current
        let isRelease = current.rawValue < previous.rawValue

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = isRelease ? GHOSTTY_ACTION_RELEASE : GHOSTTY_ACTION_PRESS
        keyEvent.mods = Self.ghosttyMods(from: event.modifierFlags)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.text = nil
        keyEvent.composing = false

        _ = ghostty_surface_key(surface, keyEvent)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        guard let surface else { return }
        let mods = Self.ghosttyMods(from: event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = Self.ghosttyMods(from: event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return }
        let mods = Self.ghosttyMods(from: event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = Self.ghosttyMods(from: event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, mods)
    }

    override func mouseMoved(with event: NSEvent) {
        sendMousePos(event)
    }

    override func mouseDragged(with event: NSEvent) {
        sendMousePos(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        sendMousePos(event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove existing tracking areas
        trackingAreas.forEach { removeTrackingArea($0) }
        // Add full-view tracking for mouseMoved
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
    }

    private func sendMousePos(_ event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        // Flip Y: NSView has origin at bottom-left, Ghostty expects top-left
        let mods = Self.ghosttyMods(from: event.modifierFlags)
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, mods)
    }

    // MARK: - Scroll Events

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }

        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY

        // Precision scrolling (trackpad) gets a speed multiplier
        if event.hasPreciseScrollingDeltas {
            x *= 2
            y *= 2
        }

        // Build scroll mods as a packed int:
        // bit 0: precision, bits 1-3: momentum
        let precision: Int32 = event.hasPreciseScrollingDeltas ? 1 : 0
        let momentum: Int32 = Self.ghosttyMomentum(from: event.momentumPhase)
        let scrollMods = ghostty_input_scroll_mods_t(precision | (momentum << 1))

        ghostty_surface_mouse_scroll(surface, x, y, scrollMods)
    }

    // MARK: - Input Helpers

    static func ghosttyMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = 0
        if flags.contains(.shift)   { mods |= UInt32(GHOSTTY_MODS_SHIFT.rawValue) }
        if flags.contains(.control) { mods |= UInt32(GHOSTTY_MODS_CTRL.rawValue) }
        if flags.contains(.option)  { mods |= UInt32(GHOSTTY_MODS_ALT.rawValue) }
        if flags.contains(.command) { mods |= UInt32(GHOSTTY_MODS_SUPER.rawValue) }
        if flags.contains(.capsLock){ mods |= UInt32(GHOSTTY_MODS_CAPS.rawValue) }
        return ghostty_input_mods_e(rawValue: mods)
    }

    static func ghosttyMomentum(from phase: NSEvent.Phase) -> Int32 {
        switch phase {
        case .began:      return Int32(GHOSTTY_MOUSE_MOMENTUM_BEGAN.rawValue)
        case .stationary: return Int32(GHOSTTY_MOUSE_MOMENTUM_STATIONARY.rawValue)
        case .changed:    return Int32(GHOSTTY_MOUSE_MOMENTUM_CHANGED.rawValue)
        case .ended:      return Int32(GHOSTTY_MOUSE_MOMENTUM_ENDED.rawValue)
        case .cancelled:  return Int32(GHOSTTY_MOUSE_MOMENTUM_CANCELLED.rawValue)
        case .mayBegin:   return Int32(GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN.rawValue)
        default:          return Int32(GHOSTTY_MOUSE_MOMENTUM_NONE.rawValue)
        }
    }
}
