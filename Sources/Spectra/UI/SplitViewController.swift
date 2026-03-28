import AppKit
import GhosttyKit

// MARK: - Split Divider

/// Divider rendered via draw(_:) — the most reliable AppKit rendering path.
/// Avoids layer?.backgroundColor which is unreliable in layer-backed hierarchies.
private class SplitDividerView: NSView {
    var color: NSColor = SpectraConfig.splitDividerColor {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
    }
}

// MARK: - Custom Split Container (replaces NSSplitView)

/// A container that divides its bounds between two child views with a draggable divider.
class SplitContainerView: NSView {
    let direction: SplitViewController.Direction
    var ratio: CGFloat = 0.5 {
        didSet {
            needsLayout = true
            window?.invalidateCursorRects(for: self)
        }
    }

    /// Visual divider thickness (the colored bar).
    private let dividerThickness: CGFloat = 4
    /// Wider invisible hit area for easier mouse targeting.
    private let hitAreaThickness: CGFloat = 8

    let firstView: NSView
    let secondView: NSView
    private let dividerView = SplitDividerView()
    private var baseDividerColor = SpectraConfig.splitDividerColor {
        didSet { if !isDragging { dividerView.color = baseDividerColor } }
    }
    private var isDragging = false

    init(direction: SplitViewController.Direction, first: NSView, second: NSView) {
        self.direction = direction
        self.firstView = first
        self.secondView = second
        super.init(frame: .zero)

        // Children are positioned by manual frame in layout(), not Auto Layout.
        // Reset in case a child was previously root with translatesAutoresizingMaskIntoConstraints = false.
        firstView.translatesAutoresizingMaskIntoConstraints = true
        secondView.translatesAutoresizingMaskIntoConstraints = true
        dividerView.color = baseDividerColor

        addSubview(firstView)
        addSubview(secondView)
        addSubview(dividerView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
        let b = bounds
        let dt = dividerThickness
        if direction == .horizontal {
            let splitX = floor(b.width * ratio)
            firstView.frame = NSRect(x: 0, y: 0, width: splitX - dt / 2, height: b.height)
            dividerView.frame = NSRect(x: splitX - dt / 2, y: 0, width: dt, height: b.height)
            secondView.frame = NSRect(x: splitX + dt / 2, y: 0,
                                       width: b.width - splitX - dt / 2, height: b.height)
        } else {
            let splitY = floor(b.height * (1 - ratio))
            firstView.frame = NSRect(x: 0, y: splitY + dt / 2,
                                      width: b.width, height: b.height - splitY - dt / 2)
            dividerView.frame = NSRect(x: 0, y: splitY - dt / 2, width: b.width, height: dt)
            secondView.frame = NSRect(x: 0, y: 0, width: b.width, height: splitY - dt / 2)
        }
    }

    // MARK: - Divider Drag Resize

    private func dividerHitRect() -> NSRect {
        let b = bounds
        let ht = hitAreaThickness
        if direction == .horizontal {
            let splitX = floor(b.width * ratio)
            return NSRect(x: splitX - ht / 2, y: 0, width: ht, height: b.height)
        } else {
            let splitY = floor(b.height * (1 - ratio))
            return NSRect(x: 0, y: splitY - ht / 2, width: b.width, height: ht)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if dividerHitRect().contains(loc) {
            isDragging = true
            dividerView.color = .controlAccentColor
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { super.mouseDragged(with: event); return }
        let loc = convert(event.locationInWindow, from: nil)
        let b = bounds
        let minRatio: CGFloat = 0.1
        let maxRatio: CGFloat = 0.9

        if direction == .horizontal {
            ratio = max(minRatio, min(maxRatio, loc.x / b.width))
        } else {
            // NSView Y is bottom-up; ratio 0.5 means top half = first
            ratio = max(minRatio, min(maxRatio, 1 - loc.y / b.height))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            dividerView.color = baseDividerColor
        } else {
            super.mouseUp(with: event)
        }
    }

    func refreshDividerColor() {
        baseDividerColor = SpectraConfig.splitDividerColor
    }

    override func resetCursorRects() {
        let cursor: NSCursor = direction == .horizontal ? .resizeLeftRight : .resizeUpDown
        addCursorRect(dividerHitRect(), cursor: cursor)
    }
}

// MARK: - SplitViewController

/// Manages a recursive tree of terminal splits within a single window.
/// Each leaf node is a PaneTabController that can host multiple terminal tabs.
class SplitViewController: NSViewController {
    private let bridge: GhosttyBridge
    private let configManager: ConfigManager
    private var rootNode: SplitNode
    private(set) var focusedTerminal: TerminalController?
    private(set) var focusedPane: PaneTabController?

    var onSurfaceClose: ((_ terminal: TerminalController) -> Void)?

    enum Direction {
        case horizontal
        case vertical
    }

    indirect enum SplitNode {
        case pane(PaneTabController)
        case split(SplitContainerView, direction: Direction, first: SplitNode, second: SplitNode)

        var view: NSView {
            switch self {
            case .pane(let ptc): return ptc.containerView
            case .split(let container, _, _, _): return container
            }
        }

        func allTerminals() -> [TerminalController] {
            switch self {
            case .pane(let ptc): return ptc.allTerminals()
            case .split(_, _, let first, let second):
                return first.allTerminals() + second.allTerminals()
            }
        }

        func allPanes() -> [PaneTabController] {
            switch self {
            case .pane(let ptc): return [ptc]
            case .split(_, _, let first, let second):
                return first.allPanes() + second.allPanes()
            }
        }
    }

    init(bridge: GhosttyBridge, configManager: ConfigManager) {
        self.bridge = bridge
        self.configManager = configManager
        let initial = PaneTabController(bridge: bridge)
        initial.addTab()
        self.rootNode = .pane(initial)
        self.focusedTerminal = initial.activeTerminal!
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        self.view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installRootView()
        setupPaneCallbacks(for: allPanes())
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSurfaceFocus(_:)),
            name: .terminalSurfaceDidFocus, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleConfigChange(_:)),
            name: GhosttyBridge.configDidChange, object: nil
        )
    }

    @objc private func handleSurfaceFocus(_ notification: Notification) {
        guard let surface = notification.object as? TerminalSurface else { return }
        // Find both terminal and its pane in one pass
        for ptc in allPanes() {
            if let tc = ptc.allTerminals().first(where: { $0.surface === surface }) {
                setExclusiveFocus(tc, in: ptc)
                return
            }
        }
    }

    @objc private func handleConfigChange(_ notification: Notification) {
        refreshDividerColors(in: rootNode)
    }

    /// Ensure only one terminal has ghostty focus.
    /// O(1) — only toggles the previous and new focus target.
    private func setExclusiveFocus(_ target: TerminalController, in pane: PaneTabController? = nil) {
        let old = focusedTerminal
        focusedTerminal = target
        focusedPane = pane ?? allPanes().first { $0.allTerminals().contains(where: { $0 === target }) }

        // Unfocus previous (if different)
        if let old = old, old !== target, let s = old.surface.surface {
            ghostty_surface_set_focus(s, false)
        }
        // Focus new
        if let s = target.surface.surface {
            ghostty_surface_set_focus(s, true)
        }
    }

    // MARK: - Public API

    func split(direction: Direction, before: Bool = false) {
        guard focusedTerminal != nil,
              let currentPTC = focusedPane else { return }

        let newPTC = PaneTabController(bridge: bridge)
        newPTC.addTab()
        setupPaneCallbacks(for: [newPTC])

        let first: SplitNode = before ? .pane(newPTC) : .pane(currentPTC)
        let second: SplitNode = before ? .pane(currentPTC) : .pane(newPTC)

        rootNode = rebuildTree(rootNode) { node in
            if case .pane(let ptc) = node, ptc === currentPTC {
                return makeSplitNode(direction: direction,
                                     first: first,
                                     second: second)
            }
            return nil
        }

        reinstallViews()

        // Force layout so views have proper bounds before surface creation.
        // ghostty's Metal sublayer frame is set at creation time; zero → stays zero.
        view.layoutSubtreeIfNeeded()

        if let app = bridge.app {
            newPTC.createSurfaces(app: app, workingDirectory: focusedTerminal?.surface.currentWorkingDirectory)
        }

        if let tc = newPTC.activeTerminal {
            setExclusiveFocus(tc, in: newPTC)
            tc.focus()
        }
    }

    /// Close an entire pane (all its tabs) from the tree.
    func closePaneTab(_ ptc: PaneTabController) {
        let panes = allPanes()
        if panes.count <= 1 {
            if let tc = ptc.activeTerminal { onSurfaceClose?(tc) }
            return
        }

        // Find the nearest sibling before removing from tree
        let sibling = findSibling(of: ptc, in: rootNode)

        ptc.detachAll()
        rootNode = removeFromTree(rootNode, target: ptc)
        reinstallViews()

        let nextPTC = sibling ?? allPanes().first
        if let next = nextPTC?.activeTerminal {
            setExclusiveFocus(next, in: nextPTC)
            next.focus()
        }
    }

    /// Open an Agents Supervisor tab in the focused pane.
    func openSupervisorTab() {
        guard let ptc = focusedPane else { return }
        let supervisor = SupervisorController()
        ptc.addCustomTab(supervisor)
        focusedTerminal = nil
        focusedPane = ptc
        supervisor.focus()
    }

    /// Add a new tab to the focused pane.
    func newPaneTab() {
        guard focusedTerminal != nil,
              let ptc = focusedPane else { return }
        let tc = ptc.addTab()
        if let app = bridge.app {
            tc.surface.createSurface(app: app, workingDirectory: focusedTerminal?.surface.currentWorkingDirectory)
        }
        setExclusiveFocus(tc, in: ptc)
        tc.focus()
    }

    /// Close the active tab (terminal or supervisor) in the focused pane.
    func closeCurrentPaneTab() {
        guard let ptc = focusedPane else { return }
        ptc.closeTab(at: ptc.activeTabIndex)
    }

    /// Navigate to next/previous tab within the focused pane.
    func nextPaneTab() {
        guard let ptc = focusedPane else { return }
        ptc.selectNextTab()
        focusActiveTab(in: ptc)
    }

    func previousPaneTab() {
        guard let ptc = focusedPane else { return }
        ptc.selectPreviousTab()
        focusActiveTab(in: ptc)
    }

    /// Focus the active tab in a pane, handling both terminal and non-terminal tabs.
    private func focusActiveTab(in ptc: PaneTabController) {
        if let tc = ptc.activeTerminal {
            setExclusiveFocus(tc, in: ptc)
            tc.focus()
        } else {
            // Non-terminal tab (e.g. supervisor) — clear terminal focus, keep pane tracked
            focusedTerminal = nil
            focusedPane = ptc
            ptc.tabs[ptc.activeTabIndex].focus()
        }
    }

    /// Navigate between split panes (cycles through active tab of each pane).
    func focusSplit(_ direction: ghostty_action_goto_split_e) {
        let panes = allPanes()
        guard panes.count > 1, let currentPane = focusedPane,
              let idx = panes.firstIndex(where: { $0 === currentPane }) else { return }

        let newIdx: Int
        switch direction {
        case GHOSTTY_GOTO_SPLIT_NEXT:     newIdx = (idx + 1) % panes.count
        case GHOSTTY_GOTO_SPLIT_PREVIOUS: newIdx = (idx - 1 + panes.count) % panes.count
        default:                           newIdx = (idx + 1) % panes.count
        }

        let nextPane = panes[newIdx]
        focusActiveTab(in: nextPane)
    }

    func allTerminals() -> [TerminalController] {
        rootNode.allTerminals()
    }

    func allPanes() -> [PaneTabController] {
        rootNode.allPanes()
    }

    /// Find the PaneTabController that contains a given terminal.
    func findPaneTab(containing tc: TerminalController) -> PaneTabController? {
        allPanes().first { ptc in
            ptc.allTerminals().contains(where: { $0 === tc })
        }
    }

    // MARK: - Layout Capture / Apply

    func captureLayout(savePaths: Bool = false) -> SplitLayoutStore.Layout {
        SplitLayoutStore.Layout(root: captureNode(rootNode, savePaths: savePaths))
    }

    private func captureNode(_ node: SplitNode, savePaths: Bool) -> SplitLayoutStore.Layout.Node {
        switch node {
        case .pane(let ptc):
            // Only serialize terminal tabs; supervisor tabs are ephemeral (Phase 1).
            let terminals = ptc.allTerminals()
            let tabs = terminals.map { tc -> TabInfo in
                let wd = savePaths ? tc.surface.currentWorkingDirectory : nil
                return TabInfo(workingDirectory: wd)
            }
            // Map the full-array activeTabIndex to the terminal-only index.
            let activeTC = ptc.activeTerminal
            let terminalActiveIdx = activeTC.flatMap { tc in terminals.firstIndex(where: { $0 === tc }) } ?? 0
            return .terminal(tabs: tabs, activeTabIndex: terminalActiveIdx)
        case .split(let container, let dir, let first, let second):
            return .split(direction: dir == .horizontal ? "horizontal" : "vertical",
                          ratio: Double(container.ratio),
                          children: [captureNode(first, savePaths: savePaths),
                                     captureNode(second, savePaths: savePaths)])
        }
    }

    func applyLayout(_ layout: SplitLayoutStore.Layout) {
        // Detach all existing terminals
        for ptc in allPanes() { ptc.detachAll() }
        var paths: [ObjectIdentifier: String] = [:]
        rootNode = buildNodeFromLayout(layout.root, paths: &paths)
        reinstallViews()
        setupPaneCallbacks(for: allPanes())

        // Force layout so views have proper bounds before surface creation.
        view.layoutSubtreeIfNeeded()

        if let app = bridge.app {
            for tc in allTerminals() {
                let wd = paths[ObjectIdentifier(tc)]
                tc.surface.createSurface(app: app, workingDirectory: wd)
            }
            // ghostty_surface_new() defaults to focused — unfocus all first,
            // then set exclusive focus on the target pane only.
            for tc in allTerminals() {
                if let s = tc.surface.surface {
                    ghostty_surface_set_focus(s, false)
                }
            }
        }
        if let firstPane = allPanes().first, let tc = firstPane.activeTerminal {
            setExclusiveFocus(tc, in: firstPane)
            tc.focus()
        }
    }

    private func buildNodeFromLayout(_ layoutNode: SplitLayoutStore.Layout.Node,
                                      paths: inout [ObjectIdentifier: String]) -> SplitNode {
        switch layoutNode {
        case .terminal(let tabInfos, let activeIndex):
            let ptc = PaneTabController(bridge: bridge)
            for info in tabInfos {
                let tc = ptc.addTab()
                if let wd = info.workingDirectory {
                    paths[ObjectIdentifier(tc)] = wd
                }
            }
            if tabInfos.isEmpty {
                ptc.addTab()
            }
            if activeIndex < ptc.tabs.count {
                ptc.selectTab(at: activeIndex)
            }
            return .pane(ptc)
        case .split(let dirStr, let ratio, let children):
            let dir: Direction = dirStr == "horizontal" ? .horizontal : .vertical
            let first = buildNodeFromLayout(children.count > 0 ? children[0] : .terminal(tabs: [.init()]), paths: &paths)
            let second = buildNodeFromLayout(children.count > 1 ? children[1] : .terminal(tabs: [.init()]), paths: &paths)
            let node = makeSplitNode(direction: dir, first: first, second: second)
            if case .split(let container, _, _, _) = node {
                container.ratio = CGFloat(ratio)
            }
            return node
        }
    }

    // MARK: - Internal

    private func installRootView() {
        let rv = rootNode.view
        rv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rv)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            rv.topAnchor.constraint(equalTo: guide.topAnchor),
            rv.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            rv.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            rv.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
        ])
    }

    private func reinstallViews() {
        view.subviews.forEach { $0.removeFromSuperview() }
        installRootView()
    }

    private func setupPaneCallbacks(for panes: [PaneTabController]) {
        for ptc in panes {
            ptc.onClose = { [weak self, weak ptc] in
                guard let self, let ptc else { return }
                self.closePaneTab(ptc)
            }
        }
    }

    /// Create a split container node with two children.
    private func makeSplitNode(direction: Direction, first: SplitNode, second: SplitNode) -> SplitNode {
        let container = SplitContainerView(direction: direction, first: first.view, second: second.view)
        return .split(container, direction: direction, first: first, second: second)
    }

    private func refreshDividerColors(in node: SplitNode) {
        switch node {
        case .pane:
            return
        case .split(let container, _, let first, let second):
            container.refreshDividerColor()
            refreshDividerColors(in: first)
            refreshDividerColors(in: second)
        }
    }

    /// Walk the tree, applying a transform function.
    private func rebuildTree(_ node: SplitNode, transform: (SplitNode) -> SplitNode?) -> SplitNode {
        if let result = transform(node) { return result }

        switch node {
        case .pane:
            return node
        case .split(_, let dir, let first, let second):
            let newFirst = rebuildTree(first, transform: transform)
            let newSecond = rebuildTree(second, transform: transform)
            return makeSplitNode(direction: dir, first: newFirst, second: newSecond)
        }
    }

    /// Find the nearest sibling pane of the target in the tree.
    /// Returns the closest pane from the other branch of the parent split.
    private func findSibling(of target: PaneTabController, in node: SplitNode) -> PaneTabController? {
        switch node {
        case .pane:
            return nil
        case .split(_, _, let first, let second):
            // If target is a direct child, return the nearest pane from the other side
            if case .pane(let ptc) = first, ptc === target {
                return second.allPanes().first
            }
            if case .pane(let ptc) = second, ptc === target {
                return first.allPanes().last
            }
            // Recurse into children
            if let result = findSibling(of: target, in: first) { return result }
            return findSibling(of: target, in: second)
        }
    }

    /// Remove a pane from the tree, collapsing its parent split to the surviving sibling.
    private func removeFromTree(_ node: SplitNode, target: PaneTabController) -> SplitNode {
        switch node {
        case .pane:
            return node
        case .split(_, _, let first, let second):
            if case .pane(let ptc) = first, ptc === target { return second }
            if case .pane(let ptc) = second, ptc === target { return first }
            let newFirst = removeFromTree(first, target: target)
            let newSecond = removeFromTree(second, target: target)
            return makeSplitNode(direction: {
                if case .split(_, let d, _, _) = node { return d }
                return .horizontal
            }(), first: newFirst, second: newSecond)
        }
    }
}
