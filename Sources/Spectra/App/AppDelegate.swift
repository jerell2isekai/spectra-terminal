import AppKit
import GhosttyKit

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shared bridge — one ghostty_app_t for the whole app.
    let bridge = GhosttyBridge()
    private var windowControllers: [MainWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        bridge.onNewTab = { [weak self] in
            self?.newTab(nil)
        }
        bridge.onNewWindow = { [weak self] in
            self?.newWindow(nil)
        }

        bridge.initialize()
        createWindow(tabIn: nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridge.shutdown()
    }

    // MARK: - Window Management

    func createWindow(tabIn existingWindow: NSWindow?) {
        let wc = MainWindowController(bridge: bridge)
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

    // MARK: - Menu Actions

    @objc func newWindow(_ sender: Any?) {
        createWindow(tabIn: nil)
    }

    @objc func newTab(_ sender: Any?) {
        let keyWindow = NSApp.keyWindow ?? windowControllers.last?.window
        createWindow(tabIn: keyWindow)
    }

    @objc func closeTab(_ sender: Any?) {
        NSApp.keyWindow?.performClose(nil)
    }

    @objc func selectNextTab(_ sender: Any?) {
        NSApp.keyWindow?.selectNextTab(nil)
    }

    @objc func selectPreviousTab(_ sender: Any?) {
        NSApp.keyWindow?.selectPreviousTab(nil)
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
        appMenu.addItem(withTitle: "Quit Spectra", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Shell menu
        let shellMenuItem = NSMenuItem()
        let shellMenu = NSMenu(title: "Shell")
        shellMenu.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
        shellMenu.addItem(withTitle: "New Tab", action: #selector(newTab(_:)), keyEquivalent: "t")
        shellMenu.addItem(.separator())
        shellMenu.addItem(withTitle: "Close", action: #selector(closeTab(_:)), keyEquivalent: "w")
        shellMenuItem.submenu = shellMenu
        mainMenu.addItem(shellMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
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

        // Cmd+1-9 for tab switching
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
