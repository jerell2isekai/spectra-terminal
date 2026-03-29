import AppKit
import GhosttyKit

/// Manages the lifecycle of a single terminal instance.
///
/// Each tab in the app gets its own TerminalController, which owns:
/// - A TerminalSurface (NSView backed by libghostty Metal renderer)
/// - A reference to the shared GhosttyBridge
class TerminalController {
    let surface: TerminalSurface
    private let bridge: GhosttyBridge
    private var currentTitle: String?
    private var titleObserver: NSObjectProtocol?

    /// Called when this terminal's surface should be closed.
    var onClose: (() -> Void)?

    init(bridge: GhosttyBridge) {
        self.bridge = bridge
        self.surface = TerminalSurface(frame: .zero)
        self.surface.onClose = { [weak self] in
            self?.onClose?()
        }
        self.titleObserver = NotificationCenter.default.addObserver(
            forName: GhosttyBridge.titleDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let info = notification.userInfo,
                  let notifSurface = info["surface"] as? ghostty_surface_t,
                  let title = info["title"] as? String,
                  let ourSurface = self.surface.surface,
                  ourSurface == notifSurface else { return }

            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            self.currentTitle = trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Attach this terminal to a container view and create the ghostty surface.
    func attach(to containerView: NSView) {
        surface.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(surface)
        // Use safeAreaLayoutGuide to avoid overlapping the title bar / traffic light buttons
        let guide = containerView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: guide.topAnchor),
            surface.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
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

    deinit {
        if let titleObserver {
            NotificationCenter.default.removeObserver(titleObserver)
        }
    }
}

// MARK: - TabContent

extension TerminalController: TabContent {
    var contentView: NSView { surface }
    var tabTitle: String { currentTitle ?? "Terminal" }
    var tabIcon: NSImage? { nil }
    var tabType: TabType { .terminal }
}
