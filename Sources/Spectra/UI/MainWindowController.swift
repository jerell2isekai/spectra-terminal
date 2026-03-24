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
    private static let toolbarID = NSToolbar.Identifier("com.spectra.mainToolbar")

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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Spectra"
        window.center()
        // Only make titlebar transparent when fully opaque; otherwise keep
        // the standard vibrancy titlebar so it doesn't become invisible.
        let hasTransparency = SpectraConfig.backgroundOpacity < 1.0
        window.titlebarAppearsTransparent = !hasTransparency
        window.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
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

        // Setup toolbar
        setupToolbar()

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

    // MARK: - Toolbar

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: Self.toolbarID)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    // MARK: - Split Actions

    func splitRight() { splitVC.split(direction: .horizontal) }
    func splitDown() { splitVC.split(direction: .vertical) }

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
        let opacity = max(0.001, min(1.0, SpectraConfig.backgroundOpacity))
        if opacity < 1.0 {
            window.isOpaque = false
            window.backgroundColor = .white.withAlphaComponent(0.001)
            window.titlebarAppearsTransparent = false  // keep titlebar visible
            window.hasShadow = true
        } else {
            window.isOpaque = true
            window.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            window.titlebarAppearsTransparent = true   // sleek look when opaque
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

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .toggleSidebar:
            return NSToolbarItem(itemIdentifier: .toggleSidebar)

        case .sidebarTrackingSeparator:
            return NSTrackingSeparatorToolbarItem(
                identifier: .sidebarTrackingSeparator,
                splitView: workspaceVC.splitView,
                dividerIndex: 0
            )

        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            .flexibleSpace,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarDefaultItemIdentifiers(toolbar)
    }
}
