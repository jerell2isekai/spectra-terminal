import AppKit

/// Manages the lifecycle of a single terminal instance.
///
/// Each tab in the app gets its own TerminalController, which owns:
/// - A TerminalSurface (NSView with Metal layer)
/// - A connection to GhosttyBridge for this surface
class TerminalController {
    let surface: TerminalSurface
    private let bridge: GhosttyBridge

    init(bridge: GhosttyBridge) {
        self.bridge = bridge
        self.surface = TerminalSurface(frame: .zero)
        self.surface.bridge = bridge
    }

    /// Attach this terminal to a container view.
    func attach(to containerView: NSView) {
        surface.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: containerView.topAnchor),
            surface.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])
        bridge.createSurface(in: surface)
    }

    /// Detach and destroy the terminal surface.
    func detach() {
        bridge.destroySurface(for: surface)
        surface.removeFromSuperview()
    }

    /// Make this terminal the first responder (focused).
    func focus() {
        surface.window?.makeFirstResponder(surface)
    }
}
