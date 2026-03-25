import AppKit

/// Top-level view controller that holds the sidebar and terminal content area side by side.
/// Uses manual Auto Layout instead of NSSplitViewController to support outset sidebar behavior
/// (window expands/shrinks when sidebar toggles, terminal pane width stays unchanged).
class WorkspaceViewController: NSViewController {

    let sidebarVC: SidebarViewController
    let terminalContentVC: SplitViewController

    private var sidebarContainer: NSVisualEffectView!
    private var sidebarWidthConstraint: NSLayoutConstraint!
    private var divider: NSView!

    /// The sidebar width when open.
    let sidebarWidth: CGFloat = 220

    init(sidebarVC: SidebarViewController, terminalContentVC: SplitViewController) {
        self.sidebarVC = sidebarVC
        self.terminalContentVC = terminalContentVC
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Sidebar container with native macOS sidebar vibrancy
        sidebarContainer = NSVisualEffectView()
        sidebarContainer.material = .sidebar
        sidebarContainer.blendingMode = .behindWindow
        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebarContainer)

        // Embed sidebar VC
        addChild(sidebarVC)
        sidebarVC.view.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.addSubview(sidebarVC.view)
        NSLayoutConstraint.activate([
            sidebarVC.view.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            sidebarVC.view.bottomAnchor.constraint(equalTo: sidebarContainer.bottomAnchor),
            sidebarVC.view.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            sidebarVC.view.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
        ])

        // 1px divider between sidebar and content
        divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        view.addSubview(divider)

        // Terminal content area
        addChild(terminalContentVC)
        terminalContentVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminalContentVC.view)

        // Layout constraints
        sidebarWidthConstraint = sidebarContainer.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            // Sidebar
            sidebarContainer.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarWidthConstraint,

            // Divider
            divider.topAnchor.constraint(equalTo: view.topAnchor),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            // Terminal content
            terminalContentVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            terminalContentVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            terminalContentVC.view.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            terminalContentVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Start collapsed
        sidebarContainer.isHidden = true
        divider.isHidden = true
    }

    // MARK: - Public API

    var isSidebarCollapsed: Bool {
        sidebarContainer.isHidden
    }

    /// Set sidebar visibility without changing the window frame.
    /// For outset behavior, the caller (MainWindowController) handles window frame adjustments.
    func setSidebarCollapsed(_ collapsed: Bool, animated: Bool = true) {
        if collapsed {
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    context.allowsImplicitAnimation = true
                    self.sidebarWidthConstraint.constant = 0
                    self.view.layoutSubtreeIfNeeded()
                }, completionHandler: {
                    self.sidebarContainer.isHidden = true
                    self.divider.isHidden = true
                })
            } else {
                sidebarWidthConstraint.constant = 0
                sidebarContainer.isHidden = true
                divider.isHidden = true
            }
        } else {
            sidebarContainer.isHidden = false
            divider.isHidden = false
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.allowsImplicitAnimation = true
                    self.sidebarWidthConstraint.constant = self.sidebarWidth
                    self.view.layoutSubtreeIfNeeded()
                }
            } else {
                sidebarWidthConstraint.constant = sidebarWidth
            }
        }
    }
}
