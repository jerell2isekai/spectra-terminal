import AppKit
import GhosttyKit

/// Manages a recursive tree of terminal splits within a single window.
///
/// Each leaf is a TerminalController. Splitting replaces a leaf with a NSSplitView
/// containing the original terminal and a new one.
class SplitViewController: NSViewController, NSSplitViewDelegate {
    private let bridge: GhosttyBridge
    private let configManager: ConfigManager
    private var rootNode: SplitNode
    private(set) var focusedTerminal: TerminalController?

    /// Called when any terminal in this split tree requests close.
    var onSurfaceClose: ((_ terminal: TerminalController) -> Void)?

    enum Direction {
        case horizontal  // side by side (split right/left)
        case vertical    // top and bottom (split down/up)
    }

    /// A node in the split tree.
    indirect enum SplitNode {
        case terminal(TerminalController)
        case split(NSSplitView, direction: Direction, first: SplitNode, second: SplitNode)

        var view: NSView {
            switch self {
            case .terminal(let tc): return tc.surface
            case .split(let sv, _, _, _): return sv
            }
        }

        /// Find the TerminalController at this node or any descendant.
        func findTerminal(_ target: TerminalController) -> Bool {
            switch self {
            case .terminal(let tc): return tc === target
            case .split(_, _, let first, let second):
                return first.findTerminal(target) || second.findTerminal(target)
            }
        }

        /// Collect all terminals in this subtree.
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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func loadView() {
        self.view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installRootView()
        setupTerminalCallbacks(for: allTerminals())
    }

    // MARK: - Public API

    /// Split the focused terminal in the given direction.
    func split(direction: Direction) {
        guard let focused = focusedTerminal else { return }

        let newTerminal = TerminalController(bridge: bridge)
        setupTerminalCallbacks(for: [newTerminal])

        rootNode = insertSplit(in: rootNode, target: focused, newTerminal: newTerminal, direction: direction)
        reinstallViews()

        // Create the surface for the new terminal after it's in the view hierarchy
        if let app = bridge.app {
            newTerminal.surface.createSurface(app: app)
        }

        // Focus the new terminal
        focusedTerminal = newTerminal
        newTerminal.focus()
    }

    /// Close a specific terminal. If it's the last one, calls onSurfaceClose.
    func closeTerminal(_ terminal: TerminalController) {
        let all = allTerminals()
        if all.count <= 1 {
            // Last terminal — close the window
            onSurfaceClose?(terminal)
            return
        }

        terminal.detach()
        rootNode = removeSplit(in: rootNode, target: terminal)
        reinstallViews()

        // Focus the first remaining terminal
        if focusedTerminal === terminal {
            focusedTerminal = allTerminals().first
            focusedTerminal?.focus()
        }
    }

    /// Focus the next or previous split relative to the currently focused one.
    func focusSplit(_ direction: ghostty_action_goto_split_e) {
        let all = allTerminals()
        guard all.count > 1, let focused = focusedTerminal,
              let idx = all.firstIndex(where: { $0 === focused }) else { return }

        let newIdx: Int
        switch direction {
        case GHOSTTY_GOTO_SPLIT_NEXT:
            newIdx = (idx + 1) % all.count
        case GHOSTTY_GOTO_SPLIT_PREVIOUS:
            newIdx = (idx - 1 + all.count) % all.count
        default:
            // For directional navigation (up/down/left/right), fall back to next/prev for now
            newIdx = (idx + 1) % all.count
        }

        focusedTerminal = all[newIdx]
        focusedTerminal?.focus()
    }

    func allTerminals() -> [TerminalController] {
        rootNode.allTerminals()
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

    /// Replace a target terminal with a split containing it and a new terminal.
    private func insertSplit(in node: SplitNode, target: TerminalController,
                             newTerminal: TerminalController, direction: Direction) -> SplitNode {
        switch node {
        case .terminal(let tc) where tc === target:
            let splitView = NSSplitView()
            splitView.isVertical = (direction == .horizontal)
            splitView.dividerStyle = .thin
            splitView.delegate = self

            let firstNode = SplitNode.terminal(tc)
            let secondNode = SplitNode.terminal(newTerminal)

            tc.surface.translatesAutoresizingMaskIntoConstraints = false
            newTerminal.surface.translatesAutoresizingMaskIntoConstraints = false
            splitView.addArrangedSubview(tc.surface)
            splitView.addArrangedSubview(newTerminal.surface)

            return .split(splitView, direction: direction, first: firstNode, second: secondNode)

        case .split(let sv, let dir, let first, let second):
            let newFirst = insertSplit(in: first, target: target, newTerminal: newTerminal, direction: direction)
            let newSecond = insertSplit(in: second, target: target, newTerminal: newTerminal, direction: direction)
            return .split(sv, direction: dir, first: newFirst, second: newSecond)

        default:
            return node
        }
    }

    /// Remove a terminal from the tree, collapsing its parent split.
    private func removeSplit(in node: SplitNode, target: TerminalController) -> SplitNode {
        switch node {
        case .terminal(let tc) where tc === target:
            // This shouldn't happen at the root (handled by closeTerminal)
            return node

        case .split(_, _, let first, let second):
            // Check if target is in first or second
            if case .terminal(let tc) = first, tc === target {
                return second
            }
            if case .terminal(let tc) = second, tc === target {
                return first
            }
            // Recurse
            let newFirst = removeSplit(in: first, target: target)
            let newSecond = removeSplit(in: second, target: target)
            // Check if a child collapsed to a different node type
            if case .split(let sv, let dir, _, _) = node {
                return .split(sv, direction: dir, first: newFirst, second: newSecond)
            }
            return node

        default:
            return node
        }
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        return max(proposedMinimumPosition, 50)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        return min(proposedMaximumPosition, total - 50)
    }
}
