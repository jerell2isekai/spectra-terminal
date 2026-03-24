import AppKit
import GhosttyKit

/// Main window with tab support. Each tab hosts a terminal.
class MainWindowController: NSWindowController {
    private let bridge = GhosttyBridge()
    private var tabs: [TabItem] = []
    private var activeTabIndex: Int = 0
    private let contentView = NSView()

    struct TabItem {
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

        // Set up bridge action handlers
        bridge.onSetTitle = { [weak self] surface, title in
            self?.handleSetTitle(surface: surface, title: title)
        }
        bridge.onNewTab = { [weak self] in
            self?.createTab()
        }

        bridge.initialize()
        createTab()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Tab Management

    private func createTab() {
        let terminal = TerminalController(bridge: bridge)
        let tab = TabItem(controller: terminal, title: "Terminal \(tabs.count + 1)")

        terminal.onClose = { [weak self] in
            self?.closeTabForController(terminal)
        }

        tabs.append(tab)
        activeTabIndex = tabs.count - 1
        showActiveTab()
    }

    private func showActiveTab() {
        guard activeTabIndex < tabs.count else { return }

        // Hide all surfaces (don't remove — surface lifecycle is separate from view hierarchy)
        for (i, tab) in tabs.enumerated() {
            if i == activeTabIndex {
                tab.controller.attach(to: contentView)
                tab.controller.focus()
            } else {
                tab.controller.surface.isHidden = true
            }
        }

        window?.title = tabs[activeTabIndex].title
    }

    private func closeTabForController(_ controller: TerminalController) {
        guard let idx = tabs.firstIndex(where: { $0.controller === controller }) else { return }
        let tab = tabs.remove(at: idx)
        tab.controller.detach()

        if tabs.isEmpty {
            window?.close()
        } else {
            activeTabIndex = min(activeTabIndex, tabs.count - 1)
            showActiveTab()
        }
    }

    // MARK: - Bridge Action Handlers

    private func handleSetTitle(surface: ghostty_surface_t, title: String) {
        for i in 0..<tabs.count {
            if tabs[i].controller.surface.surface == surface {
                tabs[i].title = title
                if i == activeTabIndex {
                    window?.title = title
                }
                break
            }
        }
    }

    // MARK: - Menu Actions

    @objc func newTab(_ sender: Any?) {
        createTab()
    }

    @objc func closeTab(_ sender: Any?) {
        guard activeTabIndex < tabs.count else {
            window?.close()
            return
        }
        closeTabForController(tabs[activeTabIndex].controller)
    }

    deinit {
        tabs.forEach { $0.controller.detach() }
        bridge.shutdown()
    }
}
