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
            return
        }

        syncSurfaceGeometry()
    }

    /// Send a command to the terminal (text + Enter key event).
    func sendCommand(_ command: String) {
        guard let surface else { return }
        // Send command text
        command.withCString { cStr in
            ghostty_surface_text(surface, cStr, UInt(command.utf8.count))
        }
        // Send Return key press (macOS keycode 36)
        var press = ghostty_input_key_s()
        press.action = GHOSTTY_ACTION_PRESS
        press.keycode = 36
        press.mods = GHOSTTY_MODS_NONE
        press.consumed_mods = GHOSTTY_MODS_NONE
        sendKey(&press, text: "\r")
        // Send Return key release
        var release = ghostty_input_key_s()
        release.action = GHOSTTY_ACTION_RELEASE
        release.keycode = 36
        release.mods = GHOSTTY_MODS_NONE
        release.consumed_mods = GHOSTTY_MODS_NONE
        _ = ghostty_surface_key(surface, release)
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

    private func syncSurfaceGeometry(size: NSSize? = nil) {
        guard let surface else { return }

        let resolvedSize = size ?? bounds.size
        let scale = window?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))

        let backed = convertToBacking(resolvedSize)
        ghostty_surface_set_size(surface, UInt32(backed.width), UInt32(backed.height))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncSurfaceGeometry(size: newSize)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncSurfaceGeometry()
    }

    // MARK: - Keyboard Events (IME-aware)

    override func keyDown(with event: NSEvent) {
        guard surface != nil else { return }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        let markedTextBefore = markedText.length > 0

        interpretKeyEvents([event])
        syncPreedit()

        if let accumulated = keyTextAccumulator, !accumulated.isEmpty {
            // IME composed text — send each piece with composing = false
            for text in accumulated {
                var keyEvent = event.ghosttyKeyEvent(action)
                keyEvent.composing = false
                sendKey(&keyEvent, text: text)
            }
        } else {
            // Normal key event — use filtered ghosttyCharacters (no PUA function keys)
            var keyEvent = event.ghosttyKeyEvent(action)
            keyEvent.composing = markedText.length > 0 || markedTextBefore
            sendKey(&keyEvent, text: keyEvent.composing ? nil : event.ghosttyCharacters)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else { return }
        let keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_RELEASE)
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else { return }
        let current = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let previous = previousModifierFlags
        previousModifierFlags = current
        let isRelease = current.rawValue < previous.rawValue

        let keyEvent = event.ghosttyKeyEvent(isRelease ? GHOSTTY_ACTION_RELEASE : GHOSTTY_ACTION_PRESS)
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

        func item(_ title: String, _ action: Selector, symbol: String) -> NSMenuItem {
            let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
            mi.target = self
            mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return mi
        }

        menu.addItem(item("Copy", #selector(contextCopy(_:)), symbol: "doc.on.doc"))
        menu.addItem(item("Paste", #selector(contextPaste(_:)), symbol: "doc.on.clipboard"))

        menu.addItem(.separator())
        menu.addItem(item("Split Right", #selector(contextSplitRight(_:)), symbol: "rectangle.split.2x1"))
        menu.addItem(item("Split Left", #selector(contextSplitLeft(_:)), symbol: "rectangle.split.2x1"))
        menu.addItem(item("Split Down", #selector(contextSplitDown(_:)), symbol: "rectangle.split.1x2"))
        menu.addItem(item("Split Up", #selector(contextSplitUp(_:)), symbol: "rectangle.split.1x2"))

        menu.addItem(.separator())
        menu.addItem(item("New Pane Tab", #selector(contextNewPaneTab(_:)), symbol: "plus.square"))
        menu.addItem(item("Close Pane Tab", #selector(contextClosePaneTab(_:)), symbol: "xmark.square"))

        menu.addItem(.separator())
        menu.addItem(item("Toggle Sidebar", #selector(contextToggleSidebar(_:)), symbol: "sidebar.left"))
        menu.addItem(item("Toggle Agent Sidecar", #selector(contextToggleSidecar(_:)), symbol: "sidebar.right"))

        menu.addItem(.separator())
        menu.addItem(item("Save Layout…", #selector(contextSaveLayout(_:)), symbol: "square.and.arrow.down"))
        menu.addItem(item("Load Layout…", #selector(contextLoadLayout(_:)), symbol: "square.and.arrow.up"))

        // Dynamic width: measure longest title + icon + margins
        let font = NSFont.menuFont(ofSize: 0)
        let maxTitle = menu.items
            .filter { !$0.isSeparatorItem }
            .map { ($0.title as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        menu.minimumWidth = maxTitle + 64  // icon (20) + leading/trailing padding

        return menu
    }

    @objc private func contextCopy(_ sender: Any?) {
        guard let surface, ghostty_surface_has_selection(surface) else { return }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text),
              let cStr = text.text else { return }
        let str = String(cString: cStr)
        ghostty_surface_free_text(surface, &text)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
    }

    @objc private func contextPaste(_ sender: Any?) {
        guard let surface,
              let str = NSPasteboard.general.string(forType: .string) else { return }
        str.withCString { cStr in
            ghostty_surface_text(surface, cStr, UInt(str.utf8.count))
        }
    }

    @objc private func contextNewPaneTab(_ sender: Any?) {
        guard let wc = window?.windowController as? MainWindowController else { return }
        wc.splitVC.newPaneTab()
    }

    @objc private func contextClosePaneTab(_ sender: Any?) {
        guard let wc = window?.windowController as? MainWindowController else { return }
        wc.splitVC.closeCurrentPaneTab()
    }

    @objc private func contextSplitRight(_ sender: Any?) {
        guard let wc = window?.windowController as? MainWindowController else { return }
        wc.splitRight()
    }

    @objc private func contextSplitLeft(_ sender: Any?) {
        guard let wc = window?.windowController as? MainWindowController else { return }
        wc.splitLeft()
    }

    @objc private func contextSplitDown(_ sender: Any?) {
        guard let wc = window?.windowController as? MainWindowController else { return }
        wc.splitDown()
    }

    @objc private func contextSplitUp(_ sender: Any?) {
        guard let wc = window?.windowController as? MainWindowController else { return }
        wc.splitUp()
    }

    @objc private func contextToggleSidebar(_ sender: Any?) {
        guard let wc = window?.windowController as? MainWindowController else { return }
        wc.toggleSidebarAction(sender)
    }

    @objc private func contextToggleSidecar(_ sender: Any?) {
        guard let wc = window?.windowController as? MainWindowController else { return }
        wc.toggleSidecarAction(sender)
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

    /// Send a key event with optional text, handling the withCString lifecycle.
    /// Only sends text for printable characters (codepoint >= 0x20); control characters
    /// are encoded by libghostty's KeyEncoder directly.
    private func sendKey(_ keyEvent: inout ghostty_input_key_s, text: String?) {
        guard let surface else { return }
        if let text, !text.isEmpty,
           let codepoint = text.utf8.first, codepoint >= 0x20 {
            text.withCString { cStr in
                keyEvent.text = cStr
                _ = ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.text = nil
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

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

// MARK: - NSEvent Ghostty Extensions

extension NSEvent {
    /// Create a ghostty_input_key_s from this NSEvent.
    ///
    /// Populates keycode, mods, consumed_mods, and unshifted_codepoint.
    /// Does NOT set text or composing — caller must handle those.
    func ghosttyKeyEvent(_ action: ghostty_input_action_e) -> ghostty_input_key_s {
        var key_ev = ghostty_input_key_s()
        key_ev.action = action
        key_ev.keycode = UInt32(keyCode)
        key_ev.text = nil
        key_ev.composing = false

        key_ev.mods = TerminalSurface.ghosttyMods(from: modifierFlags)
        // Heuristic: control and command never contribute to text translation.
        key_ev.consumed_mods = TerminalSurface.ghosttyMods(
            from: modifierFlags.subtracting([.control, .command]))

        // Unshifted codepoint for Kitty keyboard protocol.
        key_ev.unshifted_codepoint = 0
        if type == .keyDown || type == .keyUp {
            if let chars = characters(byApplyingModifiers: []),
               let codepoint = chars.unicodeScalars.first {
                key_ev.unshifted_codepoint = codepoint.value
            }
        }

        return key_ev
    }

    /// Returns filtered characters suitable for ghostty_surface_key text field.
    ///
    /// Filters out:
    /// - PUA function key characters (0xF700-0xF8FF) — arrow keys, F-keys, etc.
    /// - Control characters (< 0x20) — re-derived without control modifier.
    var ghosttyCharacters: String? {
        guard let characters else { return nil }

        if characters.count == 1,
           let scalar = characters.unicodeScalars.first {
            // Control characters are encoded by libghostty's KeyEncoder directly.
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }

            // Function keys in the macOS PUA range must not be sent as text.
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }
}
