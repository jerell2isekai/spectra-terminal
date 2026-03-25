import AppKit
import GhosttyKit

/// Manages multiple terminal tabs within a single split pane.
///
/// Sits between SplitNode leaf and TerminalController(s).
/// Tab switching uses hide/show (not destroy/recreate) to preserve scrollback and processes.
class PaneTabController {
    let containerView: NSView
    private let tabBarView: PaneTabBarView
    private let contentView: NSView
    private let bridge: GhosttyBridge
    private var tabBarHeightConstraint: NSLayoutConstraint!

    private(set) var tabs: [TerminalController] = []
    private(set) var activeTabIndex: Int = 0
    private var tabTitles: [String] = []

    /// Called when the last tab is closed — signals pane removal.
    var onClose: (() -> Void)?

    var activeTerminal: TerminalController {
        tabs[activeTabIndex]
    }

    init(bridge: GhosttyBridge) {
        self.bridge = bridge
        self.containerView = NSView()
        self.tabBarView = PaneTabBarView()
        self.contentView = NSView()

        containerView.wantsLayer = true

        tabBarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(tabBarView)
        containerView.addSubview(contentView)

        tabBarHeightConstraint = tabBarView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            tabBarView.topAnchor.constraint(equalTo: containerView.topAnchor),
            tabBarView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            tabBarHeightConstraint,

            contentView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            contentView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        tabBarView.isHidden = true
        tabBarView.delegate = self

        // Listen for terminal title changes
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleTitleChange(_:)),
            name: GhosttyBridge.titleDidChange, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Tab Management

    /// Add a new tab and return its TerminalController.
    @discardableResult
    func addTab() -> TerminalController {
        let tc = TerminalController(bridge: bridge)
        tc.onClose = { [weak self, weak tc] in
            guard let self, let tc else { return }
            if let idx = self.tabs.firstIndex(where: { $0 === tc }) {
                self.closeTab(at: idx)
            }
        }

        tabs.append(tc)
        tabTitles.append("Terminal")

        // Add surface to content view (hidden initially)
        let surface = tc.surface
        surface.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: contentView.topAnchor),
            surface.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        surface.isHidden = true

        // Switch to new tab
        selectTab(at: tabs.count - 1)
        updateTabBar()

        return tc
    }

    /// Close a tab by index. If it's the last tab, triggers onClose (pane removal).
    func closeTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }

        if tabs.count == 1 {
            // Last tab — close the whole pane.
            // Call onClose before clearing tabs so closePaneTab can still
            // access activeTerminal without index-out-of-bounds crash.
            tabs[0].detach()
            onClose?()
            tabs.removeAll()
            tabTitles.removeAll()
            return
        }

        let tc = tabs[index]
        tc.detach()
        tabs.remove(at: index)
        tabTitles.remove(at: index)

        // Adjust active index
        if activeTabIndex >= tabs.count {
            activeTabIndex = tabs.count - 1
        } else if activeTabIndex > index {
            activeTabIndex -= 1
        } else if activeTabIndex == index {
            activeTabIndex = min(index, tabs.count - 1)
        }

        // Show the now-active tab and focus it
        showOnlyActiveTab()
        updateTabBar()
        activeTerminal.focus()
    }

    /// Switch to a tab by index.
    func selectTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        activeTabIndex = index
        showOnlyActiveTab()
        updateTabBar()
    }

    /// Select the next tab (wraps around).
    func selectNextTab() {
        guard tabs.count > 1 else { return }
        selectTab(at: (activeTabIndex + 1) % tabs.count)
    }

    /// Select the previous tab (wraps around).
    func selectPreviousTab() {
        guard tabs.count > 1 else { return }
        selectTab(at: (activeTabIndex - 1 + tabs.count) % tabs.count)
    }

    /// All terminals across all tabs.
    func allTerminals() -> [TerminalController] {
        tabs
    }

    /// Detach and destroy all terminals.
    func detachAll() {
        for tc in tabs { tc.detach() }
        tabs.removeAll()
        tabTitles.removeAll()
    }

    /// Create ghostty surfaces for all tabs.
    func createSurfaces(app: ghostty_app_t, workingDirectories: [String?]? = nil) {
        for (i, tc) in tabs.enumerated() {
            let wd = workingDirectories.flatMap { i < $0.count ? $0[i] : nil }
            tc.surface.createSurface(app: app, workingDirectory: wd)
        }
    }

    /// Convenience: create surfaces with a single shared working directory.
    func createSurfaces(app: ghostty_app_t, workingDirectory: String?) {
        createSurfaces(app: app, workingDirectories: workingDirectory.map { [$0] })
    }

    // MARK: - Private

    private func showOnlyActiveTab() {
        for (i, tc) in tabs.enumerated() {
            tc.surface.isHidden = (i != activeTabIndex)
        }
    }

    private func updateTabBar() {
        let shouldShow = tabs.count > 1
        tabBarView.isHidden = !shouldShow
        tabBarHeightConstraint.constant = shouldShow ? PaneTabBarView.barHeight : 0

        if shouldShow {
            tabBarView.reload(titles: tabTitles, activeIndex: activeTabIndex)
        }
    }

    // MARK: - Title Updates

    @objc private func handleTitleChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let surface = info["surface"] as? ghostty_surface_t,
              let title = info["title"] as? String else { return }
        for (i, tc) in tabs.enumerated() {
            if let s = tc.surface.surface, s == surface {
                tabTitles[i] = title
                if tabs.count > 1 {
                    tabBarView.reload(titles: tabTitles, activeIndex: activeTabIndex)
                }
                break
            }
        }
    }
}

// MARK: - PaneTabBarDelegate

extension PaneTabController: PaneTabBarDelegate {
    func tabBar(_ tabBar: PaneTabBarView, didSelectTabAt index: Int) {
        selectTab(at: index)
        activeTerminal.focus()
    }

    func tabBar(_ tabBar: PaneTabBarView, didCloseTabAt index: Int) {
        closeTab(at: index)
    }

    func tabBarDidRequestNewTab(_ tabBar: PaneTabBarView) {
        let tc = addTab()
        if let app = bridge.app {
            tc.surface.createSurface(app: app)
        }
        activeTerminal.focus()
    }
}
