import AppKit
import GhosttyKit

/// Manages multiple tabs (terminal and non-terminal) within a single split pane.
///
/// Sits between SplitNode leaf and tab content controllers.
/// Tab switching uses hide/show (not destroy/recreate) to preserve state.
class PaneTabController {
    let containerView: NSView
    private let tabBarView: PaneTabBarView
    private let contentView: NSView
    private let bridge: GhosttyBridge
    private var tabBarHeightConstraint: NSLayoutConstraint!

    private(set) var tabs: [any TabContent] = []
    private(set) var activeTabIndex: Int = 0
    private var tabTitles: [String] = []

    /// Called when the last tab is closed — signals pane removal.
    var onClose: (() -> Void)?

    /// The active tab as a TerminalController, if it is one.
    var activeTerminal: TerminalController? {
        tabs.isEmpty ? nil : tabs[activeTabIndex] as? TerminalController
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

    /// Add a new terminal tab and return its TerminalController.
    @discardableResult
    func addTab() -> TerminalController {
        let tc = TerminalController(bridge: bridge)
        tc.onClose = { [weak self, weak tc] in
            guard let self, let tc else { return }
            if let idx = self.tabs.firstIndex(where: { $0 === tc }) {
                self.closeTab(at: idx)
            }
        }

        insertTab(tc, title: "Terminal")
        return tc
    }

    /// Add a non-terminal tab (e.g. supervisor).
    func addCustomTab(_ tab: any TabContent) {
        insertTab(tab, title: tab.tabTitle)
    }

    /// Shared logic for inserting any tab type.
    private func insertTab(_ tab: any TabContent, title: String) {
        tabs.append(tab)
        tabTitles.append(title)

        // Add content view (hidden initially)
        let view = tab.contentView
        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentView.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        view.isHidden = true

        // Switch to new tab
        selectTab(at: tabs.count - 1)
        updateTabBar()
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

        let tab = tabs[index]
        tab.detach()  // detach() is responsible for removing contentView from superview
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
        tabs[activeTabIndex].focus()
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

    /// All terminal controllers across all tabs.
    func allTerminals() -> [TerminalController] {
        tabs.compactMap { $0 as? TerminalController }
    }

    /// Detach and destroy all tabs.
    func detachAll() {
        for tab in tabs { tab.detach() }
        tabs.removeAll()
        tabTitles.removeAll()
    }

    /// Create ghostty surfaces for terminal tabs only.
    func createSurfaces(app: ghostty_app_t, workingDirectories: [String?]? = nil) {
        let terminals = allTerminals()
        for (i, tc) in terminals.enumerated() {
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
        for (i, tab) in tabs.enumerated() {
            tab.contentView.isHidden = (i != activeTabIndex)
        }
    }

    private func updateTabBar() {
        let shouldShow = tabs.count > 1
        tabBarView.isHidden = !shouldShow
        tabBarHeightConstraint.constant = shouldShow ? PaneTabBarView.barHeight : 0

        if shouldShow {
            let icons = tabs.map { $0.tabIcon }
            tabBarView.reload(titles: tabTitles, icons: icons, activeIndex: activeTabIndex)
        }
    }

    // MARK: - Title Updates

    @objc private func handleTitleChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let surface = info["surface"] as? ghostty_surface_t,
              let title = info["title"] as? String else { return }
        for (i, tab) in tabs.enumerated() {
            guard let tc = tab as? TerminalController,
                  let s = tc.surface.surface, s == surface else { continue }
            tabTitles[i] = title
            if tabs.count > 1 {
                let icons = tabs.map { $0.tabIcon }
                tabBarView.reload(titles: tabTitles, icons: icons, activeIndex: activeTabIndex)
            }
            break
        }
    }
}

// MARK: - PaneTabBarDelegate

extension PaneTabController: PaneTabBarDelegate {
    func tabBar(_ tabBar: PaneTabBarView, didSelectTabAt index: Int) {
        selectTab(at: index)
        tabs[activeTabIndex].focus()
    }

    func tabBar(_ tabBar: PaneTabBarView, didCloseTabAt index: Int) {
        closeTab(at: index)
    }

    func tabBarDidRequestNewTab(_ tabBar: PaneTabBarView) {
        let tc = addTab()
        if let app = bridge.app {
            tc.surface.createSurface(app: app)
        }
        tabs[activeTabIndex].focus()
    }
}
