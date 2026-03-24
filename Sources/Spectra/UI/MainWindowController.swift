import AppKit
import GhosttyKit

/// Each window (and each native tab) is one MainWindowController with one terminal.
class MainWindowController: NSWindowController, NSWindowDelegate {
    private let terminal: TerminalController
    private let bridge: GhosttyBridge
    private let configManager: ConfigManager

    /// Called when this window is closed and should be removed from AppDelegate's tracking.
    var onClose: (() -> Void)?

    /// Shared tabbing identifier so all Spectra windows group together.
    private static let tabbingID = "com.spectra.terminal"

    init(bridge: GhosttyBridge, configManager: ConfigManager) {
        self.bridge = bridge
        self.configManager = configManager
        self.terminal = TerminalController(bridge: bridge)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
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

        // Native macOS tab bar
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.tabbingID

        super.init(window: window)

        window.delegate = self

        // Set up the terminal surface
        let contentView = NSView()
        window.contentView = contentView
        terminal.attach(to: contentView)
        terminal.focus()

        // Handle surface close from libghostty
        terminal.onClose = { [weak self] in
            self?.window?.performClose(nil)
        }

        // Listen for notifications (works with multiple windows)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleTitleChange(_:)),
            name: GhosttyBridge.titleDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleConfigChange(_:)),
            name: GhosttyBridge.configDidChange, object: nil
        )

        // Apply initial config-driven appearance
        applyConfigAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    @objc private func handleTitleChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let surface = info["surface"],
              let title = info["title"] as? String else { return }
        // Check if this notification is for our surface
        if let ourSurface = terminal.surface.surface,
           let notifSurface = surface as? ghostty_surface_t,
           ourSurface == notifSurface {
            window?.title = title
        }
    }

    @objc private func handleConfigChange(_ notification: Notification) {
        applyConfigAppearance()
    }

    /// Apply window-level visual properties from Spectra's config.
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

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        terminal.detach()
        onClose?()
    }

    /// Called by the native tab bar "+" button.
    override func newWindowForTab(_ sender: Any?) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.createWindow(tabIn: window)
    }
}
