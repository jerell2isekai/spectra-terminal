import AppKit

/// Manages the lifecycle of a single terminal instance.
///
/// Each tab in the app gets its own TerminalController, which owns:
/// - A TerminalSurface (NSView backed by libghostty Metal renderer)
/// - A reference to the shared GhosttyBridge
class TerminalController {
    let surface: TerminalSurface
    private let bridge: GhosttyBridge

    /// Called when this terminal's surface should be closed.
    var onClose: (() -> Void)?

    init(bridge: GhosttyBridge) {
        self.bridge = bridge
        self.surface = TerminalSurface(frame: .zero)
        self.surface.onClose = { [weak self] in
            self?.onClose?()
        }
    }

    /// Attach this terminal to a container view and create the ghostty surface.
    func attach(to containerView: NSView) {
        surface.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: containerView.topAnchor),
            surface.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        if let app = bridge.app {
            surface.createSurface(app: app)
        }
    }

    /// Detach and destroy the terminal surface.
    func detach() {
        surface.destroySurface()
        surface.removeFromSuperview()
    }

    /// Make this terminal the first responder (focused).
    func focus() {
        surface.window?.makeFirstResponder(surface)
    }
}
