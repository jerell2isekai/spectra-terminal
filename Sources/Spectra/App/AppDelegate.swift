import AppKit
import GhosttyKit

class AppDelegate: NSObject, NSApplicationDelegate {
    let bridge = GhosttyBridge()
    let configManager = ConfigManager()
    private var windowControllers: [MainWindowController] = []
    private var editorControllers: [EditorWindowController] = []
    private var settingsWC: SettingsWindowController?
    private var commandPalette: CommandPaletteController?
    private var appearanceObserver: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupAppIcon()
        setupMainMenu()

        bridge.onNewTab = { [weak self] in
            self?.newTab(nil)
        }
        bridge.onNewWindow = { [weak self] in
            self?.newWindow(nil)
        }

        bridge.initialize(configManager: configManager)

        configManager.onChange = { [weak self] in
            guard let self else { return }
            self.bridge.reloadConfig()
            self.applyAppearanceMode()
            NotificationCenter.default.post(name: GhosttyBridge.configDidChange, object: nil)
        }
        configManager.startWatching()

        applyAppearanceMode()

        // Observe system appearance changes to update ghostty color scheme
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.syncColorScheme()
        }

        // Restore previous session or create a fresh window
        if !restoreSession() {
            createWindow(tabIn: nil)
        }

        // Listen for sidebar file/diff open requests
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOpenFilePreview(_:)),
            name: .sidebarOpenFilePreview, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOpenDiff(_:)),
            name: .sidebarOpenDiff, object: nil
        )

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveSession()
        configManager.stopWatching()
        bridge.shutdown()
    }

    // MARK: - App Icon

    private func setupAppIcon() {
        // When running from .app bundle, CFBundleIconFile handles the icon
        // with proper squircle mask. Only set programmatically for bare executable (dev mode).
        if Bundle.main.bundlePath.hasSuffix(".app") { return }
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }

    // MARK: - Session Persistence

    private func saveSession() {
        var windows: [SessionState.WindowState] = []

        for wc in windowControllers {
            guard let w = wc.window else { continue }
            let frame = w.frame
            let terminals = wc.splitVC.allTerminals()
            let tabs = terminals.map { tc -> SessionState.TabState in
                SessionState.TabState(
                    title: w.title,
                    workingDirectory: nil  // TODO: read PWD from ghostty surface
                )
            }
            windows.append(SessionState.WindowState(
                frame: SessionState.FrameState(
                    x: Double(frame.origin.x), y: Double(frame.origin.y),
                    width: Double(frame.width), height: Double(frame.height)
                ),
                tabs: tabs.isEmpty ? [SessionState.TabState(title: "Terminal", workingDirectory: nil)] : tabs,
                activeTabIndex: 0
            ))
        }

        if !windows.isEmpty {
            SessionState.save(SessionState(windows: windows))
        }
    }

    private func restoreSession() -> Bool {
        guard let state = SessionState.load() else { return false }
        guard !state.windows.isEmpty else { return false }

        for ws in state.windows {
            let wc = MainWindowController(bridge: bridge, configManager: configManager)
            wc.onClose = { [weak self, weak wc] in
                guard let self, let wc else { return }
                self.windowControllers.removeAll { $0 === wc }
            }
            windowControllers.append(wc)

            // Restore window frame
            let frame = NSRect(x: ws.frame.x, y: ws.frame.y,
                               width: ws.frame.width, height: ws.frame.height)
            wc.window?.setFrame(frame, display: true)
            wc.showWindow(nil)
        }

        return true
    }

    // MARK: - Window Management

    func createWindow(tabIn existingWindow: NSWindow?) {
        let wc = MainWindowController(bridge: bridge, configManager: configManager)
        wc.onClose = { [weak self, weak wc] in
            guard let self, let wc else { return }
            self.windowControllers.removeAll { $0 === wc }
        }
        windowControllers.append(wc)

        if let existingWindow {
            existingWindow.addTabbedWindow(wc.window!, ordered: .above)
            wc.window?.makeKeyAndOrderFront(nil)
        } else {
            wc.showWindow(nil)
        }
    }

    // MARK: - Command Palette

    private func buildPaletteItems() -> [CommandPaletteController.PaletteItem] {
        var items: [CommandPaletteController.PaletteItem] = []

        // Open tabs/windows
        for (i, wc) in windowControllers.enumerated() {
            let title = wc.window?.title ?? "Window \(i + 1)"
            items.append(.init(
                title: title,
                subtitle: "Window \(i + 1)",
                icon: "terminal",
                action: { [weak wc] in wc?.window?.makeKeyAndOrderFront(nil) }
            ))
        }

        // Actions
        items.append(.init(title: "New Tab", subtitle: "Cmd+T", icon: "plus.square",
                           action: { [weak self] in self?.newTab(nil) }))
        items.append(.init(title: "New Window", subtitle: "Cmd+N", icon: "macwindow.badge.plus",
                           action: { [weak self] in self?.newWindow(nil) }))
        items.append(.init(title: "Split Right", subtitle: "Cmd+D", icon: "rectangle.split.2x1",
                           action: { [weak self] in self?.splitRight(nil) }))
        items.append(.init(title: "Split Down", subtitle: "Cmd+Shift+D", icon: "rectangle.split.1x2",
                           action: { [weak self] in self?.splitDown(nil) }))
        items.append(.init(title: "New Pane Tab", subtitle: "Cmd+Opt+T", icon: "plus.rectangle.on.rectangle",
                           action: { [weak self] in self?.newPaneTab(nil) }))
        items.append(.init(title: "Next Pane Tab", subtitle: "Cmd+Opt+]", icon: "arrow.right.square",
                           action: { [weak self] in self?.nextPaneTab(nil) }))
        items.append(.init(title: "Previous Pane Tab", subtitle: "Cmd+Opt+[", icon: "arrow.left.square",
                           action: { [weak self] in self?.previousPaneTab(nil) }))
        items.append(.init(title: "Settings", subtitle: "Cmd+,", icon: "gearshape",
                           action: { [weak self] in self?.openSettings(nil) }))
        items.append(.init(title: "Toggle Sidebar", subtitle: "Cmd+\\", icon: "sidebar.left",
                           action: { [weak self] in self?.toggleSidebar(nil) }))
        items.append(.init(title: "Reload Config", subtitle: "", icon: "arrow.clockwise",
                           action: { [weak self] in self?.reloadConfig(nil) }))
        items.append(.init(title: "Open Config File", subtitle: "", icon: "doc.text",
                           action: { [weak self] in self?.openConfigFile(nil) }))

        return items
    }

    // MARK: - Menu Actions

    @objc func newWindow(_ sender: Any?) {
        createWindow(tabIn: nil)
    }

    @objc func newTab(_ sender: Any?) {
        let keyWindow = NSApp.keyWindow ?? windowControllers.last?.window
        createWindow(tabIn: keyWindow)
    }

    @objc func closeTab(_ sender: Any?) {
        // Smart close: pane tab > split pane > window
        guard let wc = NSApp.keyWindow?.windowController as? MainWindowController else {
            NSApp.keyWindow?.performClose(nil)
            return
        }
        let splitVC = wc.splitVC
        guard splitVC.focusedTerminal != nil,
              let ptc = splitVC.focusedPane else {
            NSApp.keyWindow?.performClose(nil)
            return
        }

        if ptc.tabs.count > 1 {
            splitVC.closeCurrentPaneTab()
        } else if splitVC.allPanes().count > 1 {
            splitVC.closePaneTab(ptc)
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    @objc func selectNextTab(_ sender: Any?) {
        NSApp.keyWindow?.selectNextTab(nil)
    }

    @objc func selectPreviousTab(_ sender: Any?) {
        NSApp.keyWindow?.selectPreviousTab(nil)
    }

    @objc func splitRight(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? MainWindowController else { return }
        wc.splitRight()
    }

    @objc func splitDown(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? MainWindowController else { return }
        wc.splitDown()
    }

    @objc func newPaneTab(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? MainWindowController else { return }
        wc.splitVC.newPaneTab()
    }

    @objc func nextPaneTab(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? MainWindowController else { return }
        wc.splitVC.nextPaneTab()
    }

    @objc func previousPaneTab(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? MainWindowController else { return }
        wc.splitVC.previousPaneTab()
    }

    @objc func showCommandPalette(_ sender: Any?) {
        if commandPalette == nil {
            commandPalette = CommandPaletteController()
            commandPalette?.itemProvider = { [weak self] in
                self?.buildPaletteItems() ?? []
            }
        }
        commandPalette?.showPalette()
    }

    @objc func openSettings(_ sender: Any?) {
        if settingsWC == nil {
            settingsWC = SettingsWindowController(configManager: configManager)
        }
        settingsWC?.showWindow(nil)
        settingsWC?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func openConfigFile(_ sender: Any?) {
        NSWorkspace.shared.open(SpectraConfig.configFile)
    }

    @objc func reloadConfig(_ sender: Any?) {
        configManager.reload()
    }

    // MARK: - Appearance Mode

    private func applyAppearanceMode() {
        switch SpectraConfig.appearanceMode {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil  // follow system
        }
        syncColorScheme()
    }

    private func syncColorScheme() {
        guard let app = bridge.app else { return }
        let appearance = NSApp.effectiveAppearance
        let scheme: ghostty_color_scheme_e = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? GHOSTTY_COLOR_SCHEME_DARK
            : GHOSTTY_COLOR_SCHEME_LIGHT
        ghostty_app_set_color_scheme(app, scheme)
    }

    @objc func toggleSidebar(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? MainWindowController else { return }
        wc.toggleSidebarAction(sender)
    }

    // MARK: - Editor Tabs

    @objc private func handleOpenFilePreview(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? URL else { return }
        openEditorTab(content: .filePreview(url: url))
    }

    @objc private func handleOpenDiff(_ notification: Notification) {
        guard let filePath = notification.userInfo?["filePath"] as? String,
              let repoURL = notification.userInfo?["repoURL"] as? URL else { return }
        openEditorTab(content: .diff(filePath: filePath, repoURL: repoURL))
    }

    private func openEditorTab(content: EditorWindowController.Content) {
        let editor = EditorWindowController(content: content)
        editor.onClose = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.editorControllers.removeAll { $0 === editor }
        }
        editorControllers.append(editor)

        // Add as a tab in the current window group
        if let keyWindow = NSApp.keyWindow {
            keyWindow.addTabbedWindow(editor.window!, ordered: .above)
            editor.window?.makeKeyAndOrderFront(nil)
        } else {
            editor.showWindow(nil)
        }
    }

    @objc func selectTab1(_ sender: Any?) { selectTabByIndex(0) }
    @objc func selectTab2(_ sender: Any?) { selectTabByIndex(1) }
    @objc func selectTab3(_ sender: Any?) { selectTabByIndex(2) }
    @objc func selectTab4(_ sender: Any?) { selectTabByIndex(3) }
    @objc func selectTab5(_ sender: Any?) { selectTabByIndex(4) }
    @objc func selectTab6(_ sender: Any?) { selectTabByIndex(5) }
    @objc func selectTab7(_ sender: Any?) { selectTabByIndex(6) }
    @objc func selectTab8(_ sender: Any?) { selectTabByIndex(7) }
    @objc func selectTab9(_ sender: Any?) { selectTabByIndex(8) }

    private func selectTabByIndex(_ index: Int) {
        guard let keyWindow = NSApp.keyWindow,
              let tabbedWindows = keyWindow.tabbedWindows,
              index < tabbedWindows.count else { return }
        tabbedWindows[index].makeKeyAndOrderFront(nil)
    }

    // MARK: - Main Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Spectra", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Open Config File", action: #selector(openConfigFile(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Reload Config", action: #selector(reloadConfig(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Spectra", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Shell menu
        let shellMenuItem = NSMenuItem()
        let shellMenu = NSMenu(title: "Shell")
        shellMenu.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
        shellMenu.addItem(withTitle: "New Tab", action: #selector(newTab(_:)), keyEquivalent: "t")
        shellMenu.addItem(.separator())
        shellMenu.addItem(withTitle: "Split Right", action: #selector(splitRight(_:)), keyEquivalent: "d")
        let splitDownItem = NSMenuItem(title: "Split Down", action: #selector(splitDown(_:)), keyEquivalent: "d")
        splitDownItem.keyEquivalentModifierMask = [.command, .shift]
        shellMenu.addItem(splitDownItem)
        shellMenu.addItem(.separator())
        let newPaneTabItem = NSMenuItem(title: "New Pane Tab", action: #selector(newPaneTab(_:)), keyEquivalent: "t")
        newPaneTabItem.keyEquivalentModifierMask = [.command, .option]
        shellMenu.addItem(newPaneTabItem)
        let nextPaneTabItem = NSMenuItem(title: "Next Pane Tab", action: #selector(nextPaneTab(_:)), keyEquivalent: "]")
        nextPaneTabItem.keyEquivalentModifierMask = [.command, .option]
        shellMenu.addItem(nextPaneTabItem)
        let prevPaneTabItem = NSMenuItem(title: "Previous Pane Tab", action: #selector(previousPaneTab(_:)), keyEquivalent: "[")
        prevPaneTabItem.keyEquivalentModifierMask = [.command, .option]
        shellMenu.addItem(prevPaneTabItem)
        shellMenu.addItem(.separator())
        shellMenu.addItem(withTitle: "Command Palette", action: #selector(showCommandPalette(_:)), keyEquivalent: "p")
        shellMenu.addItem(.separator())
        shellMenu.addItem(withTitle: "Close", action: #selector(closeTab(_:)), keyEquivalent: "w")
        shellMenuItem.submenu = shellMenu
        mainMenu.addItem(shellMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let toggleSidebarItem = NSMenuItem(
            title: "Toggle Sidebar",
            action: #selector(toggleSidebar(_:)),
            keyEquivalent: "\\"
        )
        viewMenu.addItem(toggleSidebarItem)
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())

        let nextTabItem = NSMenuItem(title: "Show Next Tab", action: #selector(selectNextTab(_:)), keyEquivalent: "}")
        nextTabItem.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(nextTabItem)

        let prevTabItem = NSMenuItem(title: "Show Previous Tab", action: #selector(selectPreviousTab(_:)), keyEquivalent: "{")
        prevTabItem.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(prevTabItem)

        windowMenu.addItem(.separator())

        for i in 1...9 {
            let selector = Selector("selectTab\(i):")
            let item = NSMenuItem(title: "Tab \(i)", action: selector, keyEquivalent: "\(i)")
            windowMenu.addItem(item)
        }

        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}
