import AppKit
import GhosttyKit

// MARK: - Custom Split Container (replaces NSSplitView)

/// A simple container that divides its bounds between two child views.
/// Uses manual frame calculation like Ghostty's SplitView, not NSSplitView.
class SplitContainerView: NSView {
    let direction: SplitViewController.Direction
    var ratio: CGFloat = 0.5
    private let dividerThickness: CGFloat = 1

    let firstView: NSView
    let secondView: NSView
    private let dividerView = NSView()

    init(direction: SplitViewController.Direction, first: NSView, second: NSView) {
        self.direction = direction
        self.firstView = first
        self.secondView = second
        super.init(frame: .zero)

        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = NSColor.separatorColor.cgColor

        addSubview(firstView)
        addSubview(secondView)
        addSubview(dividerView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let b = bounds
        if direction == .horizontal {
            let splitX = floor(b.width * ratio)
            firstView.frame = NSRect(x: 0, y: 0, width: splitX, height: b.height)
            dividerView.frame = NSRect(x: splitX, y: 0, width: dividerThickness, height: b.height)
            secondView.frame = NSRect(x: splitX + dividerThickness, y: 0,
                                       width: b.width - splitX - dividerThickness, height: b.height)
        } else {
            // Vertical: first on top, second on bottom (NSView origin is bottom-left)
            let splitY = floor(b.height * (1 - ratio))
            firstView.frame = NSRect(x: 0, y: splitY + dividerThickness,
                                      width: b.width, height: b.height - splitY - dividerThickness)
            dividerView.frame = NSRect(x: 0, y: splitY, width: b.width, height: dividerThickness)
            secondView.frame = NSRect(x: 0, y: 0, width: b.width, height: splitY)
        }
    }
}

// MARK: - SplitViewController

/// Manages a recursive tree of terminal splits within a single window.
class SplitViewController: NSViewController {
    private let bridge: GhosttyBridge
    private let configManager: ConfigManager
    private var rootNode: SplitNode
    private(set) var focusedTerminal: TerminalController?

    var onSurfaceClose: ((_ terminal: TerminalController) -> Void)?

    enum Direction {
        case horizontal
        case vertical
    }

    indirect enum SplitNode {
        case terminal(TerminalController)
        case split(SplitContainerView, direction: Direction, first: SplitNode, second: SplitNode)

        var view: NSView {
            switch self {
            case .terminal(let tc): return tc.surface
            case .split(let container, _, _, _): return container
            }
        }

        func allTerminals() -> [TerminalController] {
            switch self {
            case .terminal(let tc): return [tc]
            case .split(_, _, let first, let second):
                return first.allTerminals() + second.allTerminals()
            }
        }
    }

    init(bridge: GhosttyBridge, configManager: ConfigManager) {
        self.bridge = bridge
        self.configManager = configManager
        let initial = TerminalController(bridge: bridge)
        self.rootNode = .terminal(initial)
        self.focusedTerminal = initial
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        self.view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installRootView()
        setupTerminalCallbacks(for: allTerminals())
    }

    // MARK: - Public API

    func split(direction: Direction) {
        guard let focused = focusedTerminal else { return }

        let newTerminal = TerminalController(bridge: bridge)
        setupTerminalCallbacks(for: [newTerminal])

        // Rebuild tree: old leaf becomes a split with old + new
        rootNode = rebuildTree(rootNode) { node in
            if case .terminal(let tc) = node, tc === focused {
                return makeSplitNode(direction: direction,
                                     first: .terminal(tc),
                                     second: .terminal(newTerminal))
            }
            return nil  // no change
        }

        reinstallViews()

        if let app = bridge.app {
            newTerminal.surface.createSurface(app: app)
        }

        focusedTerminal = newTerminal
        newTerminal.focus()
    }

    func closeTerminal(_ terminal: TerminalController) {
        let all = allTerminals()
        if all.count <= 1 {
            onSurfaceClose?(terminal)
            return
        }

        terminal.detach()
        rootNode = removeFromTree(rootNode, target: terminal)
        reinstallViews()

        if focusedTerminal === terminal {
            focusedTerminal = allTerminals().first
            focusedTerminal?.focus()
        }
    }

    func focusSplit(_ direction: ghostty_action_goto_split_e) {
        let all = allTerminals()
        guard all.count > 1, let focused = focusedTerminal,
              let idx = all.firstIndex(where: { $0 === focused }) else { return }

        let newIdx: Int
        switch direction {
        case GHOSTTY_GOTO_SPLIT_NEXT:     newIdx = (idx + 1) % all.count
        case GHOSTTY_GOTO_SPLIT_PREVIOUS: newIdx = (idx - 1 + all.count) % all.count
        default:                           newIdx = (idx + 1) % all.count
        }

        focusedTerminal = all[newIdx]
        focusedTerminal?.focus()
    }

    func allTerminals() -> [TerminalController] {
        rootNode.allTerminals()
    }

    // MARK: - Layout Capture / Apply

    func captureLayout() -> SplitLayoutStore.Layout {
        SplitLayoutStore.Layout(root: captureNode(rootNode))
    }

    private func captureNode(_ node: SplitNode) -> SplitLayoutStore.Layout.Node {
        switch node {
        case .terminal: return .terminal
        case .split(_, let dir, let first, let second):
            return .split(direction: dir == .horizontal ? "horizontal" : "vertical",
                          children: [captureNode(first), captureNode(second)])
        }
    }

    func applyLayout(_ layout: SplitLayoutStore.Layout) {
        for tc in allTerminals() { tc.detach() }
        rootNode = buildNodeFromLayout(layout.root)
        reinstallViews()
        setupTerminalCallbacks(for: allTerminals())
        if let app = bridge.app {
            for tc in allTerminals() { tc.surface.createSurface(app: app) }
        }
        focusedTerminal = allTerminals().first
        focusedTerminal?.focus()
    }

    private func buildNodeFromLayout(_ layoutNode: SplitLayoutStore.Layout.Node) -> SplitNode {
        switch layoutNode {
        case .terminal:
            return .terminal(TerminalController(bridge: bridge))
        case .split(let dirStr, let children):
            let dir: Direction = dirStr == "horizontal" ? .horizontal : .vertical
            let first = buildNodeFromLayout(children.count > 0 ? children[0] : .terminal)
            let second = buildNodeFromLayout(children.count > 1 ? children[1] : .terminal)
            return makeSplitNode(direction: dir, first: first, second: second)
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

    private func setupTerminalCallbacks(for terminals: [TerminalController]) {
        for tc in terminals {
            tc.onClose = { [weak self, weak tc] in
                guard let self, let tc else { return }
                self.closeTerminal(tc)
            }
        }
    }

    /// Create a split container node with two children.
    private func makeSplitNode(direction: Direction, first: SplitNode, second: SplitNode) -> SplitNode {
        let container = SplitContainerView(direction: direction, first: first.view, second: second.view)
        return .split(container, direction: direction, first: first, second: second)
    }

    /// Walk the tree, applying a transform function. If the transform returns a node, use it; otherwise recurse.
    private func rebuildTree(_ node: SplitNode, transform: (SplitNode) -> SplitNode?) -> SplitNode {
        // Try to transform this node directly
        if let result = transform(node) { return result }

        // Otherwise recurse into splits
        switch node {
        case .terminal:
            return node
        case .split(_, let dir, let first, let second):
            let newFirst = rebuildTree(first, transform: transform)
            let newSecond = rebuildTree(second, transform: transform)
            return makeSplitNode(direction: dir, first: newFirst, second: newSecond)
        }
    }

    /// Remove a terminal from the tree, collapsing its parent split to the surviving sibling.
    private func removeFromTree(_ node: SplitNode, target: TerminalController) -> SplitNode {
        switch node {
        case .terminal:
            return node
        case .split(_, _, let first, let second):
            if case .terminal(let tc) = first, tc === target { return second }
            if case .terminal(let tc) = second, tc === target { return first }
            let newFirst = removeFromTree(first, target: target)
            let newSecond = removeFromTree(second, target: target)
            return makeSplitNode(direction: {
                if case .split(_, let d, _, _) = node { return d }
                return .horizontal
            }(), first: newFirst, second: newSecond)
        }
    }
}
