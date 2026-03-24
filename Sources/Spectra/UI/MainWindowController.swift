import AppKit

/// Main window with tab support. Each tab hosts a terminal.
class MainWindowController: NSWindowController {
    private let bridge = GhosttyBridge()
    private var tabs: [TabItem] = []
    private var activeTabIndex: Int = 0
    private let contentView = NSView()

    struct TabItem {
        let id: String
        let controller: TerminalController
        var title: String
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Spectra"
        window.center()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        window.minSize = NSSize(width: 400, height: 300)
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.contentView = contentView
        bridge.initialize()
        createTab()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Tab Management

    private func createTab() {
        let terminal = TerminalController(bridge: bridge)
        let id = "tab-\(Date().timeIntervalSince1970)-\(tabs.count)"
        let tab = TabItem(id: id, controller: terminal, title: "Terminal \(tabs.count + 1)")
        tabs.append(tab)
        activeTabIndex = tabs.count - 1
        showActiveTab()
    }

    private func showActiveTab() {
        // Remove all subviews
        contentView.subviews.forEach { $0.removeFromSuperview() }

        guard activeTabIndex < tabs.count else { return }
        let tab = tabs[activeTabIndex]
        tab.controller.attach(to: contentView)
        tab.controller.focus()
        window?.title = tab.title
    }

    @objc func newTab(_ sender: Any?) {
        createTab()
    }

    @objc func closeTab(_ sender: Any?) {
        guard !tabs.isEmpty else {
            window?.close()
            return
        }

        let tab = tabs.remove(at: activeTabIndex)
        tab.controller.detach()

        if tabs.isEmpty {
            window?.close()
        } else {
            activeTabIndex = min(activeTabIndex, tabs.count - 1)
            showActiveTab()
        }
    }

    deinit {
        tabs.forEach { $0.controller.detach() }
        bridge.shutdown()
    }
}
