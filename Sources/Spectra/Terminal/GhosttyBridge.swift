import Foundation
// import GhosttyKit  // Uncomment after libghostty is built

/// Bridge between Swift and libghostty's C API.
///
/// This class wraps the opaque `ghostty_app_t` handle and provides the
/// runtime callbacks that libghostty's embedded apprt requires:
///
///   - wakeup: trigger a tick of the event loop
///   - action: handle agent actions (new window, set title, open URL, etc.)
///   - read_clipboard / write_clipboard: clipboard access
///   - close_surface: close a terminal surface
///
/// Reference: Ghostty's macOS app at /macos/Sources/Ghostty/Ghostty.App.swift
class GhosttyBridge {

    // MARK: - Placeholder types (replace with GhosttyKit types after build)

    // These represent the opaque handles from ghostty.h:
    //   ghostty_app_t     — the application instance
    //   ghostty_surface_t — a single terminal surface
    //   ghostty_config_t  — configuration handle

    /// Initialize libghostty with the embedded apprt.
    ///
    /// Steps (to implement after libghostty is built):
    /// 1. Create a `ghostty_config_t` with desired settings
    /// 2. Populate a `ghostty_runtime_config_s` with callback function pointers
    /// 3. Call `ghostty_app_new(runtime_config, config)` to get `ghostty_app_t`
    func initialize() {
        // TODO: After building libghostty:
        //
        // var runtimeConfig = ghostty_runtime_config_s()
        // runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        // runtimeConfig.wakeup = { userdata in
        //     // Post to main run loop to trigger a tick
        //     DispatchQueue.main.async { /* tick */ }
        // }
        // runtimeConfig.action = { userdata, action in
        //     // Handle: new_window, set_title, open_url, etc.
        // }
        // runtimeConfig.read_clipboard = { userdata, location, state in
        //     let pb = NSPasteboard.general
        //     return pb.string(forType: .string)
        // }
        // runtimeConfig.write_clipboard = { userdata, text, location, confirm in
        //     let pb = NSPasteboard.general
        //     pb.clearContents()
        //     pb.setString(String(cString: text), forType: .string)
        // }
        //
        // let config = ghostty_config_new()
        // ghostty_config_load_default(config)
        //
        // app = ghostty_app_new(&runtimeConfig, config)
        // ghostty_config_free(config)

        print("[GhosttyBridge] initialize() — stub, build libghostty first")
    }

    /// Create a new terminal surface in the given NSView.
    /// The Metal renderer will draw into this view's layer.
    func createSurface(in view: NSView) {
        // TODO: After building libghostty:
        //
        // let metalLayer = view.layer as! CAMetalLayer
        // let surface = ghostty_surface_new(app, metalLayer, view.bounds.size)
        // surfaces[view] = surface

        print("[GhosttyBridge] createSurface() — stub")
    }

    /// Destroy a terminal surface.
    func destroySurface(for view: NSView) {
        // TODO: ghostty_surface_free(surfaces[view])
        print("[GhosttyBridge] destroySurface() — stub")
    }

    /// Forward a key event to libghostty.
    func sendKeyEvent(_ event: NSEvent, to view: NSView) {
        // TODO: ghostty_surface_key(surface, event)
    }

    /// Forward a mouse event to libghostty.
    func sendMouseEvent(_ event: NSEvent, to view: NSView) {
        // TODO: ghostty_surface_mouse(surface, event)
    }

    /// Forward a scroll event to libghostty.
    func sendScrollEvent(_ event: NSEvent, to view: NSView) {
        // TODO: ghostty_surface_scroll(surface, event)
    }

    /// Notify libghostty that a surface was resized.
    func surfaceDidResize(_ view: NSView) {
        // TODO: ghostty_surface_set_size(surface, view.bounds.size)
    }

    /// Tick the libghostty event loop. Called from the wakeup callback.
    func tick() {
        // TODO: ghostty_app_tick(app)
    }

    /// Shut down libghostty.
    func shutdown() {
        // TODO: ghostty_app_free(app)
        print("[GhosttyBridge] shutdown()")
    }
}
