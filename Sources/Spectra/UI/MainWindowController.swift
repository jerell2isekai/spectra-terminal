import AppKit
import GhosttyKit

/// Each window (and each native tab) is one MainWindowController with a split-capable terminal.
class MainWindowController: NSWindowController, NSWindowDelegate {
    let splitVC: SplitViewController
    private let bridge: GhosttyBridge
    private let configManager: ConfigManager

    var onClose: (() -> Void)?
    private static let tabbingID = "com.spectra.terminal"

    init(bridge: GhosttyBridge, configManager: ConfigManager) {
        self.bridge = bridge
        self.configManager = configManager
        self.splitVC = SplitViewController(bridge: bridge, configManager: configManager)

        let cfg = configManager.config
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: CGFloat(cfg.general.windowWidth),
                                height: CGFloat(cfg.general.windowHeight)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Spectra"
        window.center()
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        window.minSize = NSSize(width: 400, height: 300)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.tabbingID

        super.init(window: window)

        window.delegate = self
        window.contentViewController = splitVC

        // Create initial surface after view is in hierarchy
        if let app = bridge.app {
            splitVC.allTerminals().first?.surface.createSurface(app: app)
        }
        splitVC.focusedTerminal?.focus()

        // Handle last terminal close → close window
        splitVC.onSurfaceClose = { [weak self] _ in
            self?.window?.performClose(nil)
        }

        // Notifications
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleTitleChange(_:)),
            name: GhosttyBridge.titleDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleConfigChange(_:)),
            name: GhosttyBridge.configDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSplitRequest(_:)),
            name: GhosttyBridge.splitRequested, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleGotoSplit(_:)),
            name: GhosttyBridge.gotoSplitRequested, object: nil
        )

        applyConfigAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Split Actions

    func splitRight() { splitVC.split(direction: .horizontal) }
    func splitDown() { splitVC.split(direction: .vertical) }

    // MARK: - Notifications

    @objc private func handleTitleChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let surface = info["surface"],
              let title = info["title"] as? String else { return }
        // Update title if the focused terminal's surface matches
        if let focused = splitVC.focusedTerminal,
           let ourSurface = focused.surface.surface,
           let notifSurface = surface as? ghostty_surface_t,
           ourSurface == notifSurface {
            window?.title = title
        }
    }

    @objc private func handleConfigChange(_ notification: Notification) {
        applyConfigAppearance()
    }

    private func applyConfigAppearance() {
        guard let window else { return }
        let opacity = max(0.001, min(1.0, configManager.config.appearance.backgroundOpacity))
        if opacity < 1.0 {
            window.isOpaque = false
            window.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: opacity)
        } else {
            window.isOpaque = true
            window.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        }
    }

    @objc private func handleSplitRequest(_ notification: Notification) {
        guard window?.isKeyWindow == true,
              let dir = notification.userInfo?["direction"] as? ghostty_action_split_direction_e else { return }
        switch dir {
        case GHOSTTY_SPLIT_DIRECTION_RIGHT, GHOSTTY_SPLIT_DIRECTION_LEFT:
            splitRight()
        case GHOSTTY_SPLIT_DIRECTION_DOWN, GHOSTTY_SPLIT_DIRECTION_UP:
            splitDown()
        default:
            splitRight()
        }
    }

    @objc private func handleGotoSplit(_ notification: Notification) {
        guard window?.isKeyWindow == true,
              let dir = notification.userInfo?["direction"] as? ghostty_action_goto_split_e else { return }
        splitVC.focusSplit(dir)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        for tc in splitVC.allTerminals() {
            tc.detach()
        }
        onClose?()
    }

    override func newWindowForTab(_ sender: Any?) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.createWindow(tabIn: window)
    }
}
