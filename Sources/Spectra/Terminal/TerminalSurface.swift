import AppKit
import GhosttyKit
import QuartzCore

/// NSView subclass that hosts a terminal surface backed by libghostty's Metal renderer.
///
/// Each instance owns a `ghostty_surface_t` and forwards input events directly.
/// Implements NSTextInputClient for IME (CJK input method) support.
class TerminalSurface: NSView, NSTextInputClient {
    private(set) var surface: ghostty_surface_t?
    private var previousModifierFlags: NSEvent.ModifierFlags = []

    /// Called when libghostty requests this surface be closed.
    var onClose: (() -> Void)?

    // MARK: - Working Directory

    /// Current working directory reported by the shell via OSC 7.
    var currentWorkingDirectory: String?

    // MARK: - IME State

    /// Stores the current IME composition (preedit) text.
    private var markedText = NSMutableAttributedString()
    /// Accumulates committed text during a single keyDown cycle.
    /// Non-nil means we're inside keyDown processing.
    private var keyTextAccumulator: [String]?

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
    }

    // MARK: - Surface Lifecycle

    func createSurface(app: ghostty_app_t, workingDirectory: String? = nil) {
        guard self.surface == nil else { return }

        var cfg = ghostty_surface_config_new()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform.macos.nsview = Unmanaged.passUnretained(self).toOpaque()
        cfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        cfg.scale_factor = Double(window?.screen?.backingScaleFactor
                                  ?? NSScreen.main?.backingScaleFactor ?? 1.0)
        cfg.font_size = 0
        cfg.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        if let wd = workingDirectory {
            wd.withCString { cStr in
                cfg.working_directory = cStr
                self.surface = ghostty_surface_new(app, &cfg)
            }
        } else {
            self.surface = ghostty_surface_new(app, &cfg)
        }
        if self.surface == nil {
            print("[TerminalSurface] ghostty_surface_new() failed")
        }
    }

    /// Send a command to the terminal (text + Enter key event).
    func sendCommand(_ command: String) {
        guard let surface else { return }
        // Send command text
        command.withCString { cStr in
            ghostty_surface_text(surface, cStr, UInt(command.utf8.count))
        }
        // Send Return key press (macOS keycode 36)
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.mods = GHOSTTY_MODS_NONE
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.keycode = 36
        keyEvent.composing = false
        "\r".withCString { cStr in
            keyEvent.text = cStr
            _ = ghostty_surface_key(surface, keyEvent)
        }
        // Send Return key release
        keyEvent.action = GHOSTTY_ACTION_RELEASE
        keyEvent.text = nil
        _ = ghostty_surface_key(surface, keyEvent)
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
        if let surface { ghostty_surface_set_focus(surface, true) }
        NotificationCenter.default.post(name: .terminalSurfaceDidFocus, object: self)
        return true
    }

    override func resignFirstResponder() -> Bool {
        if let surface { ghostty_surface_set_focus(surface, false) }
        return true
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface else { return }
        let scale = window?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
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

    // MARK: - Keyboard Events (IME-aware)

    override func keyDown(with event: NSEvent) {
        guard surface != nil else { return }

        let hadMarkedText = markedText.length > 0
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        // Let AppKit / IME process the key — this triggers NSTextInputClient methods
        interpretKeyEvents([event])

        // After interpretKeyEvents, sync preedit state to ghostty
        syncPreedit()

        // Process any accumulated committed text
        if let accumulated = keyTextAccumulator, !accumulated.isEmpty {
            for text in accumulated {
                text.withCString { cStr in
                    ghostty_surface_text(surface, cStr, UInt(text.utf8.count))
                }
            }
        } else if markedText.length == 0 && !hadMarkedText {
            // No IME involvement — send as raw key event
            let mods = Self.ghosttyMods(from: event.modifierFlags)
            var keyEvent = ghostty_input_key_s()
            keyEvent.action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
            keyEvent.mods = mods
            keyEvent.consumed_mods = GHOSTTY_MODS_NONE
            keyEvent.keycode = UInt32(event.keyCode)
            keyEvent.composing = false

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

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let chars: String
        if let s = string as? String { chars = s }
        else if let a = string as? NSAttributedString { chars = a.string }
        else { return }

        // Clear composition
        markedText = NSMutableAttributedString()

        if keyTextAccumulator != nil {
            // Inside keyDown — accumulate for deferred send
            keyTextAccumulator?.append(chars)
        } else {
            // Outside keyDown (e.g., paste via IME) — send immediately
            guard let surface else { return }
            syncPreedit()
            chars.withCString { cStr in
                ghostty_surface_text(surface, cStr, UInt(chars.utf8.count))
            }
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let s = string as? String {
            markedText = NSMutableAttributedString(string: s)
        } else if let a = string as? NSAttributedString {
            markedText = NSMutableAttributedString(attributedString: a)
        }

        // If outside keyDown, sync immediately
        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        markedText = NSMutableAttributedString()
        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        markedText.length > 0 ? NSRange(location: 0, length: markedText.length) : NSRange(location: NSNotFound, length: 0)
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    override func doCommand(by selector: Selector) {
        // Intentionally empty — suppress NSBeep for unhandled selectors.
        // The terminal handles all keyboard input via ghostty_surface_key/text.
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface, let win = window else { return .zero }

        var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)

        // Convert from surface coords (top-left origin) to window coords (bottom-left origin)
        let localPoint = NSPoint(x: x, y: frame.height - y - h)
        let windowPoint = convert(localPoint, to: nil)
        let screenPoint = win.convertPoint(toScreen: windowPoint)
        return NSRect(x: screenPoint.x, y: screenPoint.y, width: w, height: h)
    }

    /// Sync the current preedit (marked text) state to libghostty.
    private func syncPreedit() {
        guard let surface else { return }
        if markedText.length > 0 {
            let str = markedText.string
            str.withCString { cStr in
                ghostty_surface_preedit(surface, cStr, UInt(str.utf8.count))
            }
        } else {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Split Right", action: #selector(contextSplitRight(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Split Down", action: #selector(contextSplitDown(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Save Layout…", action: #selector(contextSaveLayout(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Load Layout…", action: #selector(contextLoadLayout(_:)), keyEquivalent: "")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func contextSplitRight(_ sender: Any?) {
        guard let wc = window?.windowController as? MainWindowController else { return }
        wc.splitRight()
    }

    @objc private func contextSplitDown(_ sender: Any?) {
        guard let wc = window?.windowController as? MainWindowController else { return }
        wc.splitDown()
    }

    @objc private func contextSaveLayout(_ sender: Any?) {
        guard let wc = window?.windowController as? MainWindowController,
              let win = window else { return }

        let existing = SplitLayoutStore.list()
        let alert = NSAlert()
        alert.messageText = "Save Split Layout"
        alert.informativeText = existing.isEmpty
            ? "Enter a name for this layout:"
            : "Enter a new name, or pick an existing layout to overwrite:"

        // Fixed-size container with popup + text field + checkboxes
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 112))

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 84, width: 260, height: 25))
        popup.addItem(withTitle: "New layout")
        for name in existing {
            popup.addItem(withTitle: "Overwrite: \(name)")
            popup.lastItem?.representedObject = name
        }
        container.addSubview(popup)

        let nameField = NSTextField(frame: NSRect(x: 0, y: 54, width: 260, height: 24))
        nameField.placeholderString = "e.g. dev-2col"
        container.addSubview(nameField)

        let savePathsCheck = NSButton(checkboxWithTitle: "Save working directories",
                                       target: nil, action: nil)
        savePathsCheck.frame = NSRect(x: 0, y: 26, width: 260, height: 22)
        savePathsCheck.state = .on
        container.addSubview(savePathsCheck)

        let saveSidebarCheck = NSButton(checkboxWithTitle: "Save sidebar directory",
                                         target: nil, action: nil)
        saveSidebarCheck.frame = NSRect(x: 0, y: 0, width: 260, height: 22)
        saveSidebarCheck.state = .on
        container.addSubview(saveSidebarCheck)

        alert.accessoryView = container
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: win) { response in
            guard response == .alertFirstButtonReturn else { return }
            let savePaths = savePathsCheck.state == .on
            var layout = wc.splitVC.captureLayout(savePaths: savePaths)
            if saveSidebarCheck.state == .on {
                layout.sidebarDirectory = wc.sidebarRootPath
                layout.sidebarOpen = wc.isSidebarOpen
            }

            if let overwriteName = popup.selectedItem?.representedObject as? String {
                SplitLayoutStore.save(layout: layout, name: overwriteName)
            } else {
                let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                SplitLayoutStore.save(layout: layout, name: name)
            }
        }
    }

    @objc private func contextLoadLayout(_ sender: Any?) {
        guard let wc = window?.windowController as? MainWindowController,
              let win = window else { return }
        let names = SplitLayoutStore.list()
        guard !names.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Saved Layouts"
            alert.informativeText = "Save a layout first via right-click → Save Layout."
            alert.beginSheetModal(for: win) { _ in }
            return
        }

        let alert = NSAlert()
        alert.messageText = "Load Split Layout"
        alert.informativeText = "Choose a layout to restore:"
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 25))
        popup.addItems(withTitles: names)
        alert.accessoryView = popup
        alert.addButton(withTitle: "Load")
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: win) { response in
            guard let name = popup.titleOfSelectedItem else { return }
            if response == .alertFirstButtonReturn {
                guard let layout = SplitLayoutStore.load(name: name) else { return }
                wc.splitVC.applyLayout(layout)
                if let sidebarDir = layout.sidebarDirectory {
                    wc.setSidebarRootDirectory(sidebarDir)
                }
                if let sidebarOpen = layout.sidebarOpen {
                    wc.setSidebarOpen(sidebarOpen)
                    UserDefaults.standard.set(sidebarOpen, forKey: "sidebarOpen")
                }
            } else if response == .alertSecondButtonReturn {
                SplitLayoutStore.delete(name: name)
            }
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT,
                                          Self.ghosttyMods(from: event.modifierFlags))
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT,
                                          Self.ghosttyMods(from: event.modifierFlags))
    }

    override func rightMouseDown(with event: NSEvent) {
        // Show context menu instead of forwarding to ghostty
        if let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    override func rightMouseUp(with event: NSEvent) {}

    override func mouseMoved(with event: NSEvent) { sendMousePos(event) }
    override func mouseDragged(with event: NSEvent) { sendMousePos(event) }
    override func rightMouseDragged(with event: NSEvent) { sendMousePos(event) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    private func sendMousePos(_ event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y,
                                   Self.ghosttyMods(from: event.modifierFlags))
    }

    // MARK: - Scroll Events

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas { x *= 2; y *= 2 }
        let precision: Int32 = event.hasPreciseScrollingDeltas ? 1 : 0
        let momentum: Int32 = Self.ghosttyMomentum(from: event.momentumPhase)
        ghostty_surface_mouse_scroll(surface, x, y,
                                      ghostty_input_scroll_mods_t(precision | (momentum << 1)))
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
