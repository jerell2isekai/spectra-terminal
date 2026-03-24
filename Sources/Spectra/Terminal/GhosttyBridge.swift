import AppKit
import GhosttyKit

/// Bridge between Swift and libghostty's C API.
///
/// Owns the `ghostty_app_t` handle and runtime callbacks.
/// Each TerminalSurface creates its own `ghostty_surface_t` via this bridge's app handle.
class GhosttyBridge {

    // MARK: - State

    private(set) var app: ghostty_app_t?
    private var config: ghostty_config_t?
    private weak var configManager: ConfigManager?

    /// Action handlers — set by AppDelegate for app-level actions.
    var onNewTab: (() -> Void)?
    var onNewWindow: (() -> Void)?

    // MARK: - Notifications

    /// userInfo: ["surface": ghostty_surface_t, "title": String]
    static let titleDidChange = Notification.Name("GhosttyBridgeTitleDidChange")
    /// userInfo: ["config": ghostty_config_t] — posted after config reload or change
    static let configDidChange = Notification.Name("GhosttyBridgeConfigDidChange")

    // MARK: - Lifecycle

    /// Initialize with a ConfigManager that provides Spectra's own config.
    func initialize(configManager: ConfigManager) {
        self.configManager = configManager

        // 1. Create ghostty config from Spectra's TOML config (not ghostty's default files)
        guard let cfg = configManager.createGhosttyConfig() else {
            print("[GhosttyBridge] Failed to create ghostty config from Spectra config")
            return
        }
        self.config = cfg

        // 2. Build runtime config with C callbacks
        var rt = ghostty_runtime_config_s()
        rt.userdata = Unmanaged.passUnretained(self).toOpaque()
        rt.supports_selection_clipboard = false
        rt.wakeup_cb = GhosttyBridge.wakeupCallback
        rt.action_cb = GhosttyBridge.actionCallback
        rt.read_clipboard_cb = GhosttyBridge.readClipboardCallback
        rt.confirm_read_clipboard_cb = GhosttyBridge.confirmReadClipboardCallback
        rt.write_clipboard_cb = GhosttyBridge.writeClipboardCallback
        rt.close_surface_cb = GhosttyBridge.closeSurfaceCallback

        // 3. Create the app
        self.app = ghostty_app_new(&rt, cfg)
        guard self.app != nil else {
            print("[GhosttyBridge] ghostty_app_new() failed")
            return
        }

        // Set initial focus state
        ghostty_app_set_focus(self.app, NSApp.isActive)
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    /// Reload configuration from Spectra's config manager and apply to all surfaces.
    func reloadConfig() {
        guard let app, let configManager else { return }
        guard let newCfg = configManager.createGhosttyConfig() else { return }

        let oldConfig = self.config
        self.config = newCfg
        ghostty_app_update_config(app, newCfg)
        if let oldConfig { ghostty_config_free(oldConfig) }
    }

    /// Open Spectra's config file in the default editor.
    func openConfig() {
        NSWorkspace.shared.open(SpectraConfig.configFile)
    }


    /// Shut down libghostty. Must be called on the main thread before this object is deallocated
    /// to avoid racing with in-flight wakeup callbacks dispatched via DispatchQueue.main.async.
    func shutdown() {
        assert(Thread.isMainThread, "shutdown() must be called on the main thread")
        if let app {
            ghostty_app_free(app)
            self.app = nil
        }
        if let config {
            ghostty_config_free(config)
            self.config = nil
        }
    }

    // MARK: - C Callbacks (static, C calling convention)

    /// Called from any thread when libghostty needs processing.
    private static let wakeupCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ud in
        guard let ud else { return }
        let bridge = Unmanaged<GhosttyBridge>.fromOpaque(ud).takeUnretainedValue()
        DispatchQueue.main.async {
            bridge.tick()
        }
    }

    /// Handle actions from libghostty (set_title, new_tab, quit, etc.).
    private static let actionCallback: @convention(c) (
        ghostty_app_t?, ghostty_target_s, ghostty_action_s
    ) -> Bool = { app, target, action in
        guard let app else { return false }
        guard let ud = ghostty_app_userdata(app) else { return false }
        let bridge = Unmanaged<GhosttyBridge>.fromOpaque(ud).takeUnretainedValue()

        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            if let cTitle = action.action.set_title.title {
                let title = String(cString: cTitle)
                if target.tag == GHOSTTY_TARGET_SURFACE {
                    let surface = target.target.surface as Any
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: GhosttyBridge.titleDidChange,
                            object: nil,
                            userInfo: ["surface": surface, "title": title]
                        )
                    }
                }
            }
            return true

        case GHOSTTY_ACTION_NEW_TAB:
            DispatchQueue.main.async { bridge.onNewTab?() }
            return true

        case GHOSTTY_ACTION_NEW_WINDOW:
            DispatchQueue.main.async { bridge.onNewWindow?() }
            return true

        case GHOSTTY_ACTION_QUIT:
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true

        case GHOSTTY_ACTION_RENDER:
            // Rendering is handled by Metal/CAMetalLayer — nothing to do here
            return true

        case GHOSTTY_ACTION_RELOAD_CONFIG:
            let soft = action.action.reload_config.soft
            DispatchQueue.main.async {
                if soft {
                    if let app = bridge.app, let cfg = bridge.config {
                        ghostty_app_update_config(app, cfg)
                    }
                } else {
                    bridge.reloadConfig()
                }
            }
            return true

        case GHOSTTY_ACTION_CONFIG_CHANGE:
            let newCfg = action.action.config_change.config as Any
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: GhosttyBridge.configDidChange,
                    object: nil,
                    userInfo: ["config": newCfg]
                )
            }
            return true

        case GHOSTTY_ACTION_OPEN_CONFIG:
            DispatchQueue.main.async { bridge.openConfig() }
            return true

        case GHOSTTY_ACTION_COLOR_CHANGE:
            // Color changes are applied internally by libghostty's renderer
            return true

        case GHOSTTY_ACTION_MOUSE_SHAPE:
            return false

        case GHOSTTY_ACTION_MOUSE_VISIBILITY:
            return false

        case GHOSTTY_ACTION_RING_BELL:
            NSSound.beep()
            return true

        default:
            return false
        }
    }

    /// Read clipboard content for a surface.
    private static let readClipboardCallback: @convention(c) (
        UnsafeMutableRawPointer?, ghostty_clipboard_e, UnsafeMutableRawPointer?
    ) -> Bool = { surfaceUD, location, state in
        guard let state else { return false }
        // macOS only has the general pasteboard (no X11-style selection clipboard)
        let pb: NSPasteboard = .general

        guard let str = pb.string(forType: .string) else { return false }

        // Get the surface handle from the TerminalSurface's userdata
        guard let surfaceUD else { return false }
        let surface = Unmanaged<TerminalSurface>.fromOpaque(surfaceUD).takeUnretainedValue()
        guard let surfaceHandle = surface.surface else { return false }

        str.withCString { cStr in
            ghostty_surface_complete_clipboard_request(surfaceHandle, cStr, state, true)
        }
        return true
    }

    /// Confirm clipboard read (for unsafe paste detection).
    /// TODO: Phase 2 — show NSAlert confirmation dialog for GHOSTTY_CLIPBOARD_REQUEST_PASTE
    /// to protect against bracket-paste attacks. Currently auto-confirms all requests.
    private static let confirmReadClipboardCallback: @convention(c) (
        UnsafeMutableRawPointer?, UnsafePointer<CChar>?,
        UnsafeMutableRawPointer?, ghostty_clipboard_request_e
    ) -> Void = { surfaceUD, cStr, state, request in
        guard let surfaceUD, let state else { return }
        let surface = Unmanaged<TerminalSurface>.fromOpaque(surfaceUD).takeUnretainedValue()
        guard let surfaceHandle = surface.surface else { return }
        ghostty_surface_complete_clipboard_request(surfaceHandle, cStr, state, true)
    }

    /// Write to clipboard from a surface.
    private static let writeClipboardCallback: @convention(c) (
        UnsafeMutableRawPointer?, ghostty_clipboard_e,
        UnsafePointer<ghostty_clipboard_content_s>?, Int, Bool
    ) -> Void = { _, location, content, len, _ in
        guard let content, len > 0 else { return }
        let pb: NSPasteboard = .general
        pb.clearContents()

        for i in 0..<len {
            let item = content[i]
            if let data = item.data {
                let str = String(cString: data)
                pb.setString(str, forType: .string)
                break  // Only handle first text item
            }
        }
    }

    /// Called when a surface should be closed.
    private static let closeSurfaceCallback: @convention(c) (
        UnsafeMutableRawPointer?, Bool
    ) -> Void = { surfaceUD, processAlive in
        guard let surfaceUD else { return }
        let surface = Unmanaged<TerminalSurface>.fromOpaque(surfaceUD).takeUnretainedValue()
        DispatchQueue.main.async {
            surface.onClose?()
        }
    }
}
