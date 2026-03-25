import AppKit
import GhosttyKit

/// Each window (and each native tab) is one MainWindowController with a split-capable terminal.
class MainWindowController: NSWindowController, NSWindowDelegate {
    let splitVC: SplitViewController
    private let workspaceVC: WorkspaceViewController
    private let sidebarVC: SidebarViewController
    private let bridge: GhosttyBridge
    private let configManager: ConfigManager

    var onClose: (() -> Void)?
    private static let tabbingID = "com.spectra.terminal"

    init(bridge: GhosttyBridge, configManager: ConfigManager) {
        self.bridge = bridge
        self.configManager = configManager
        self.splitVC = SplitViewController(bridge: bridge, configManager: configManager)
        self.sidebarVC = SidebarViewController()
        self.workspaceVC = WorkspaceViewController(
            sidebarVC: sidebarVC,
            terminalContentVC: splitVC
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: CGFloat(SpectraConfig.windowWidth),
                                height: CGFloat(SpectraConfig.windowHeight)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Spectra"
        window.center()
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 400, height: 300)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.tabbingID

        super.init(window: window)

        window.delegate = self
        window.contentViewController = workspaceVC

        // Restore sidebar state from last session
        let sidebarWasOpen = UserDefaults.standard.bool(forKey: "sidebarOpen")
        workspaceVC.setSidebarCollapsed(!sidebarWasOpen, animated: false)

        // Create initial surface after view is in hierarchy
        if let app = bridge.app {
            splitVC.allTerminals().first?.surface.createSurface(app: app)
        }
        splitVC.focusedTerminal?.focus()

        // Handle last terminal close -> close window
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
    func splitLeft() { splitVC.split(direction: .horizontal, before: true) }
    func splitDown() { splitVC.split(direction: .vertical) }
    func splitUp() { splitVC.split(direction: .vertical, before: true) }

    /// Current sidebar root directory path (nil if not set).
    var sidebarRootPath: String? {
        sidebarVC.rootURL?.path
    }

    /// Set the sidebar's root directory.
    func setSidebarRootDirectory(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        sidebarVC.setRootDirectory(url)
    }

    /// Whether the sidebar is currently open.
    var isSidebarOpen: Bool {
        !workspaceVC.isSidebarCollapsed
    }

    /// Set sidebar open/closed state.
    func setSidebarOpen(_ open: Bool, animated: Bool = true) {
        workspaceVC.setSidebarCollapsed(!open, animated: animated)
    }

    // MARK: - Sidebar Actions

    @objc func toggleSidebarAction(_ sender: Any?) {
        workspaceVC.toggleSidebar(sender)
        // Persist sidebar state after toggle animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(self.isSidebarOpen, forKey: "sidebarOpen")
        }
    }

    // MARK: - Notifications

    @objc private func handleTitleChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let surface = info["surface"],
              let title = info["title"] as? String else { return }
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
        let opacity = max(0.001, min(1.0, SpectraConfig.backgroundOpacity))
        if opacity < 1.0 {
            window.isOpaque = false
            // Use .white (not .windowBackgroundColor) to match Terminal.app transparency behavior
            window.backgroundColor = .white.withAlphaComponent(0.001)
            window.hasShadow = true

            // Apply background blur via the private CGSSetWindowBackgroundBlurRadius API.
            // ghostty_set_window_background_blur reads background-blur and background-opacity
            // from the app config and applies the appropriate blur radius.
            if let app = bridge.app {
                ghostty_set_window_background_blur(app, Unmanaged.passUnretained(window).toOpaque())
            }
        } else {
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
        }
    }

    @objc private func handleSplitRequest(_ notification: Notification) {
        guard window?.isKeyWindow == true,
              let dir = notification.userInfo?["direction"] as? ghostty_action_split_direction_e else { return }
        switch dir {
        case GHOSTTY_SPLIT_DIRECTION_RIGHT:
            splitRight()
        case GHOSTTY_SPLIT_DIRECTION_LEFT:
            splitLeft()
        case GHOSTTY_SPLIT_DIRECTION_DOWN:
            splitDown()
        case GHOSTTY_SPLIT_DIRECTION_UP:
            splitUp()
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
        for ptc in splitVC.allPanes() {
            ptc.detachAll()
        }
        onClose?()
    }

    override func newWindowForTab(_ sender: Any?) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.createWindow(tabIn: window)
    }
}

