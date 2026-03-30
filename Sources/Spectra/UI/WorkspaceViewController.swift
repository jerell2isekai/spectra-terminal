import AppKit

/// Top-level view controller that holds the sidebar and terminal content area side by side.
/// Uses manual Auto Layout instead of NSSplitViewController to support outset sidebar behavior
/// (window expands/shrinks when sidebar toggles, terminal pane width stays unchanged).
class WorkspaceViewController: NSViewController {

    let sidebarVC: SidebarViewController
    let terminalContentVC: SplitViewController

    private var sidebarContainer: NSVisualEffectView!
    private(set) var sidebarWidthConstraint: NSLayoutConstraint!
    private var divider: DividerView!
    private(set) var currentOverlay: OverlayPanel?


    /// The default sidebar width when first opened.
    static let defaultSidebarWidth: CGFloat = 220
    private static let minSidebarWidth: CGFloat = 150
    private static let maxSidebarWidth: CGFloat = 500

    /// The current sidebar width (persisted via UserDefaults).
    var sidebarWidth: CGFloat = {
        let saved = CGFloat(UserDefaults.standard.double(forKey: "sidebarWidth"))
        return saved >= minSidebarWidth ? saved : defaultSidebarWidth
    }()


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

        // Draggable divider between sidebar and content
        divider = DividerView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.onDrag = { [weak self] deltaX in self?.handleDividerDrag(deltaX) }
        view.addSubview(divider)

        // Terminal content area
        addChild(terminalContentVC)
        terminalContentVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminalContentVC.view)


        // Layout constraints
        sidebarWidthConstraint = sidebarContainer.widthAnchor.constraint(equalToConstant: 0)

        var constraints: [NSLayoutConstraint] = [
            // Left sidebar
            sidebarContainer.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarWidthConstraint,

            // Left divider — 6px wide for easy grab, visually thin via layer
            divider.topAnchor.constraint(equalTo: view.topAnchor),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 6),

            // Terminal content
            terminalContentVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            terminalContentVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            terminalContentVC.view.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
        ]

        constraints.append(terminalContentVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor))

        NSLayoutConstraint.activate(constraints)

        // Start collapsed
        sidebarContainer.isHidden = true
        divider.isHidden = true
    }

    // MARK: - Overlay

    /// Show an overlay panel on top of the entire workspace (sidebar + terminal).
    @discardableResult
    func showOverlay(title: String, content: NSView, size: OverlayPanel.Size = .large) -> OverlayPanel {
        // Dismiss any existing overlay first
        currentOverlay?.dismiss()

        let overlay = OverlayPanel(title: title, size: size)
        overlay.setContent(content)
        overlay.internalDismissHandler = { [weak self] in
            self?.currentOverlay = nil
        }
        overlay.show(in: view)
        currentOverlay = overlay
        return overlay
    }

    func dismissOverlay() {
        currentOverlay?.dismiss()
    }

    var isOverlayVisible: Bool {
        currentOverlay != nil
    }

    // MARK: - Divider Drag

    private func handleDividerDrag(_ deltaX: CGFloat) {
        guard !isSidebarCollapsed else { return }

        let newWidth = (sidebarWidthConstraint.constant + deltaX)
            .clamped(to: Self.minSidebarWidth...Self.maxSidebarWidth)

        guard abs(newWidth - sidebarWidthConstraint.constant) > 0.5 else { return }

        sidebarWidthConstraint.constant = newWidth
        sidebarWidth = newWidth
        UserDefaults.standard.set(Double(newWidth), forKey: "sidebarWidth")
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

// MARK: - Draggable Divider View

private class DividerView: NSView {
    var onDrag: ((CGFloat) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // Draw 1px line centered in the 6px hit area
        NSColor.separatorColor.setFill()
        let lineRect = NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height)
        lineRect.fill()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        // Absorb — drag handled in mouseDragged
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(event.deltaX)
    }
}

// MARK: - CGFloat Clamping

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
