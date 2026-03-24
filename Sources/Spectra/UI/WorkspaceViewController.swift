import AppKit

/// Top-level NSSplitViewController that holds the sidebar and the terminal content area.
/// The sidebar uses `.sidebar` behavior for native macOS sidebar appearance (vibrancy, collapse, etc.).
/// The content area wraps the existing SplitViewController (recursive terminal splits).
class WorkspaceViewController: NSSplitViewController {

    let sidebarVC: SidebarViewController
    let terminalContentVC: SplitViewController

    init(sidebarVC: SidebarViewController, terminalContentVC: SplitViewController) {
        self.sidebarVC = sidebarVC
        self.terminalContentVC = terminalContentVC
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Sidebar item — native macOS sidebar behavior with vibrancy, collapsible
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.canCollapse = true
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 400
        addSplitViewItem(sidebarItem)

        // Content item — the existing terminal split tree
        let contentItem = NSSplitViewItem(viewController: terminalContentVC)
        contentItem.minimumThickness = 300
        addSplitViewItem(contentItem)

        splitView.dividerStyle = .thin
        splitView.autosaveName = "com.spectra.workspaceSplit"
    }

    // MARK: - Public API

    var isSidebarCollapsed: Bool {
        splitViewItems.first?.isCollapsed ?? true
    }

    func setSidebarCollapsed(_ collapsed: Bool, animated: Bool = true) {
        guard let sidebarItem = splitViewItems.first else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                sidebarItem.animator().isCollapsed = collapsed
            }
        } else {
            sidebarItem.isCollapsed = collapsed
        }
    }
}
