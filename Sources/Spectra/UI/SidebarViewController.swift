import AppKit

// MARK: - Shared UI Fonts

private func sidebarUIFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    let psName: String
    switch weight {
    case .semibold, .bold, .medium: psName = "Sarasa-UI-TC-SemiBold"
    case .light:                    psName = "Sarasa-UI-TC-Light"
    default:                        psName = "Sarasa-UI-TC-Regular"
    }
    return NSFont(name: psName, size: size) ?? .systemFont(ofSize: size, weight: weight)
}

private func sidebarUIMonoFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    let psName = weight == .bold || weight == .semibold
        ? "Sarasa-Mono-TC-SemiBold" : "Sarasa-Mono-TC-Regular"
    return NSFont(name: psName, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
}

// MARK: - Constants

private let activityBarWidth: CGFloat = 40

// MARK: - SidebarPanel

private enum SidebarPanel: Int, CaseIterable {
    case files = 0
    case git = 1

    var iconName: String {
        switch self {
        case .files: return "doc.text"
        case .git:   return "arrow.triangle.branch"
        }
    }

    var title: String {
        switch self {
        case .files: return "FILES"
        case .git:   return "SOURCE CONTROL"
        }
    }
}

// MARK: - ActivityBarView

fileprivate protocol ActivityBarDelegate: AnyObject {
    func activityBar(_ bar: ActivityBarView, didSelectPanel panel: SidebarPanel)
}

private class ActivityBarView: NSView {

    weak var delegate: ActivityBarDelegate?

    private let stack = NSStackView()
    private var itemContainers: [SidebarPanel: NSView] = [:]
    private var buttons: [SidebarPanel: NSButton] = [:]
    private var badges: [SidebarPanel: NSTextField] = [:]
    private var currentPanel: SidebarPanel = .files

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        for panel in SidebarPanel.allCases {
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false

            let button = NSButton()
            button.bezelStyle = .toolbar
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.tag = panel.rawValue
            button.target = self
            button.action = #selector(itemClicked(_:))
            button.translatesAutoresizingMaskIntoConstraints = false

            if let image = NSImage(systemSymbolName: panel.iconName,
                                   accessibilityDescription: panel.title) {
                let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
                let configured = image.withSymbolConfiguration(config) ?? image
                configured.isTemplate = true
                button.image = configured
            }

            button.setAccessibilityRole(.radioButton)
            button.setAccessibilityLabel(panel.title)

            container.addSubview(button)

            let badge = NSTextField(labelWithString: "")
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.font = .monospacedSystemFont(ofSize: 9, weight: .bold)
            badge.alignment = .center
            badge.textColor = .white
            badge.wantsLayer = true
            badge.isHidden = true
            container.addSubview(badge)

            NSLayoutConstraint.activate([
                container.widthAnchor.constraint(equalToConstant: activityBarWidth),
                container.heightAnchor.constraint(equalToConstant: 36),
                button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 32),
                button.heightAnchor.constraint(equalToConstant: 32),
                badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
                badge.heightAnchor.constraint(equalToConstant: 14),
                badge.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
                badge.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
            ])

            stack.addArrangedSubview(container)
            itemContainers[panel] = container
            buttons[panel] = button
            badges[panel] = badge
        }

        updateHighlight()
    }

    @objc private func itemClicked(_ sender: NSButton) {
        guard let panel = SidebarPanel(rawValue: sender.tag) else { return }
        delegate?.activityBar(self, didSelectPanel: panel)
    }

    func setActivePanel(_ panel: SidebarPanel) {
        currentPanel = panel
        updateHighlight()
    }

    func setBadge(_ count: Int, for panel: SidebarPanel) {
        guard let badge = badges[panel] else { return }
        if count > 0 {
            badge.stringValue = count > 99 ? "99+" : "\(count)"
            badge.isHidden = false
            badge.layer?.cornerRadius = 7
            badge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        } else {
            badge.isHidden = true
        }
    }

    private func updateHighlight() {
        for panel in SidebarPanel.allCases {
            let isActive = panel == currentPanel
            buttons[panel]?.contentTintColor = isActive
                ? .controlAccentColor
                : .secondaryLabelColor
            buttons[panel]?.setAccessibilityValue(isActive ? "1" : "0")
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 1px separator on the right edge
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
    }
}

// MARK: - PanelHeaderView

private class PanelHeaderView: NSView {

    var onOpenFolder: (() -> Void)?
    var onToggleHiddenFiles: (() -> Void)?
    var onRefresh: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "FILES")
    private let rootLabel = NSTextField(labelWithString: "No Folder Open")
    private let buttonStack = NSStackView()
    private let openFolderButton: NSButton
    private let showHiddenFilesButton: NSButton
    private let refreshButton: NSButton

    override init(frame frameRect: NSRect) {
        openFolderButton = NSButton(
            image: NSImage(systemSymbolName: "folder.badge.plus",
                           accessibilityDescription: "Open Folder")!,
            target: nil, action: nil)
        showHiddenFilesButton = NSButton(
            image: NSImage(systemSymbolName: "eye.slash",
                           accessibilityDescription: "Show Hidden Files")!,
            target: nil, action: nil)
        refreshButton = NSButton(
            image: NSImage(systemSymbolName: "arrow.clockwise",
                           accessibilityDescription: "Refresh")!,
            target: nil, action: nil)

        super.init(frame: frameRect)

        openFolderButton.target = self
        openFolderButton.action = #selector(openFolderClicked)
        showHiddenFilesButton.target = self
        showHiddenFilesButton.action = #selector(toggleHiddenClicked)
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)

        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = sidebarUIFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(titleLabel)

        rootLabel.translatesAutoresizingMaskIntoConstraints = false
        rootLabel.font = sidebarUIFont(ofSize: 10)
        rootLabel.textColor = .tertiaryLabelColor
        rootLabel.lineBreakMode = .byTruncatingMiddle
        rootLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(rootLabel)

        for btn in [openFolderButton, showHiddenFilesButton, refreshButton] {
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.bezelStyle = .accessoryBarAction
            btn.controlSize = .small
            btn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        }
        openFolderButton.toolTip = "Open Folder"
        refreshButton.toolTip = "Refresh"

        buttonStack.orientation = .horizontal
        buttonStack.spacing = 2
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.setHuggingPriority(.defaultHigh, for: .horizontal)
        buttonStack.addArrangedSubview(openFolderButton)
        buttonStack.addArrangedSubview(showHiddenFilesButton)
        buttonStack.addArrangedSubview(refreshButton)
        addSubview(buttonStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            rootLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            rootLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: rootLabel.trailingAnchor, constant: 4),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func setPanel(_ panel: SidebarPanel) {
        titleLabel.stringValue = panel.title
        showHiddenFilesButton.isHidden = panel != .files
    }

    func setRootName(_ name: String) {
        rootLabel.stringValue = name
    }

    func updateHiddenFilesIcon(showing: Bool) {
        let symbolName = showing ? "eye" : "eye.slash"
        let desc = showing ? "Hide Hidden Files" : "Show Hidden Files"
        showHiddenFilesButton.image = NSImage(systemSymbolName: symbolName,
                                              accessibilityDescription: desc)
        showHiddenFilesButton.toolTip = desc
    }

    @objc private func openFolderClicked() { onOpenFolder?() }
    @objc private func toggleHiddenClicked() { onToggleHiddenFiles?() }
    @objc private func refreshClicked() { onRefresh?() }
}

// MARK: - SidebarViewController

/// Sidebar with VS Code-style activity bar (icon strip) and switchable panels.
class SidebarViewController: NSViewController {

    // MARK: - Layout Components
    private var activityBar: ActivityBarView!
    private var panelHeader: PanelHeaderView!

    // MARK: - File Tree
    private var outlineView: NSOutlineView!
    private var fileTreeScrollView: NSScrollView!

    // MARK: - Source Control (full height)
    private var gitInfoLabel: NSTextField!
    private var gitChangesTable: NSTableView!
    private var gitScrollView: NSScrollView!

    // MARK: - State
    private var activePanel: SidebarPanel = .files
    private var rootNode: FileNode?
    private(set) var rootURL: URL?
    private var showsHiddenFiles: Bool = UserDefaults.standard.bool(forKey: "sidebarShowHiddenFiles")
    private var cachedGitStatuses: [String: FileNode.GitStatus] = [:]
    private var gitStatusGeneration: Int = 0
    private var discoveredRepos: [GitStatusProvider.RepoInfo] = []
    private var gitRows: [GitRow] = []
    private lazy var gitAutoRefreshMonitor: GitAutoRefreshMonitor = {
        let monitor = GitAutoRefreshMonitor()
        monitor.onRefreshRequested = { [weak self] trigger in
            self?.performGitStatusRefresh(trigger: trigger)
        }
        return monitor
    }()

    enum GitRow {
        case repoHeader(name: String, branch: String, changeCount: Int)
        case changedFile(path: String, status: FileNode.GitStatus, repoURL: URL)
    }

    private let fileColumnID = NSUserInterfaceItemIdentifier("FileColumn")
    private let gitFileColumnID = NSUserInterfaceItemIdentifier("GitFileColumn")

    override func loadView() {
        let container = NSView()

        activityBar = ActivityBarView()
        activityBar.delegate = self

        panelHeader = PanelHeaderView()
        panelHeader.onOpenFolder = { [weak self] in self?.openFolder(nil) }
        panelHeader.onToggleHiddenFiles = { [weak self] in self?.toggleShowHiddenFiles(nil) }
        panelHeader.onRefresh = { [weak self] in self?.refreshTree(nil) }
        panelHeader.updateHiddenFilesIcon(showing: showsHiddenFiles)

        buildFileTree()
        buildGitPanel()

        // Panel area container
        let panelArea = NSView()
        panelArea.translatesAutoresizingMaskIntoConstraints = false
        panelArea.addSubview(panelHeader)
        panelArea.addSubview(fileTreeScrollView)
        panelArea.addSubview(gitScrollView)

        container.addSubview(activityBar)
        container.addSubview(panelArea)

        let safeArea = container.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            // Activity bar — left side, full height
            activityBar.topAnchor.constraint(equalTo: safeArea.topAnchor),
            activityBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            activityBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            activityBar.widthAnchor.constraint(equalToConstant: activityBarWidth),

            // Panel area — right of activity bar
            panelArea.topAnchor.constraint(equalTo: safeArea.topAnchor),
            panelArea.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            panelArea.leadingAnchor.constraint(equalTo: activityBar.trailingAnchor),
            panelArea.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // Panel header — top of panel area
            panelHeader.topAnchor.constraint(equalTo: panelArea.topAnchor),
            panelHeader.leadingAnchor.constraint(equalTo: panelArea.leadingAnchor),
            panelHeader.trailingAnchor.constraint(equalTo: panelArea.trailingAnchor),

            // File tree — below header
            fileTreeScrollView.topAnchor.constraint(equalTo: panelHeader.bottomAnchor),
            fileTreeScrollView.leadingAnchor.constraint(equalTo: panelArea.leadingAnchor),
            fileTreeScrollView.trailingAnchor.constraint(equalTo: panelArea.trailingAnchor),
            fileTreeScrollView.bottomAnchor.constraint(equalTo: panelArea.bottomAnchor),

            // Git panel — same position, toggled via isHidden
            gitScrollView.topAnchor.constraint(equalTo: panelHeader.bottomAnchor),
            gitScrollView.leadingAnchor.constraint(equalTo: panelArea.leadingAnchor),
            gitScrollView.trailingAnchor.constraint(equalTo: panelArea.trailingAnchor),
            gitScrollView.bottomAnchor.constraint(equalTo: panelArea.bottomAnchor),
        ])

        // Start on Files tab
        gitScrollView.isHidden = true
        panelHeader.setPanel(.files)

        self.view = container
    }

    // MARK: - Build File Tree

    private func buildFileTree() {
        outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.focusRingType = .none
        outlineView.rowSizeStyle = .medium
        outlineView.selectionHighlightStyle = .regular
        outlineView.floatsGroupRows = false
        outlineView.indentationPerLevel = 14
        outlineView.autoresizesOutlineColumn = true
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let column = NSTableColumn(identifier: fileColumnID)
        column.title = "Name"
        column.minWidth = 50
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.action = #selector(outlineViewClicked(_:))
        outlineView.doubleAction = #selector(outlineViewDoubleClicked(_:))
        outlineView.target = self

        fileTreeScrollView = NSScrollView()
        fileTreeScrollView.documentView = outlineView
        fileTreeScrollView.hasVerticalScroller = true
        fileTreeScrollView.hasHorizontalScroller = false
        fileTreeScrollView.autohidesScrollers = true
        fileTreeScrollView.drawsBackground = false
        fileTreeScrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Build Git Panel (full height)

    private func buildGitPanel() {
        gitChangesTable = NSTableView()
        gitChangesTable.headerView = nil
        gitChangesTable.focusRingType = .none
        gitChangesTable.rowSizeStyle = .medium
        gitChangesTable.selectionHighlightStyle = .regular
        gitChangesTable.rowHeight = 20

        let gitColumn = NSTableColumn(identifier: gitFileColumnID)
        gitColumn.title = ""
        gitColumn.isEditable = false
        gitColumn.resizingMask = .autoresizingMask
        gitChangesTable.addTableColumn(gitColumn)
        gitChangesTable.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        gitChangesTable.dataSource = self
        gitChangesTable.delegate = self
        gitChangesTable.action = #selector(gitChangesTableClicked(_:))
        gitChangesTable.target = self

        gitScrollView = NSScrollView()
        gitScrollView.documentView = gitChangesTable
        gitScrollView.hasVerticalScroller = true
        gitScrollView.hasHorizontalScroller = false
        gitScrollView.autohidesScrollers = true
        gitScrollView.drawsBackground = false
        gitScrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Public API

    func setRootDirectory(_ url: URL) {
        rootURL = url
        gitStatusGeneration += 1
        cachedGitStatuses = [:]
        rootNode = FileNode(url: url)
        rootNode?.loadChildren(showHiddenFiles: showsHiddenFiles)
        panelHeader.setRootName(url.lastPathComponent)
        outlineView.reloadData()
        if rootNode != nil {
            outlineView.expandItem(rootNode)
        }
        gitAutoRefreshMonitor.startMonitoring(rootURL: url)
        gitAutoRefreshMonitor.requestImmediateRefresh(.rootChanged)
    }

    func setGitRefreshWindowFocused(_ focused: Bool) {
        gitAutoRefreshMonitor.setWindowFocused(focused)
    }

    func stopGitAutoRefreshMonitoring() {
        gitAutoRefreshMonitor.stopMonitoring()
    }

    // MARK: - Panel Switching (centralized)

    private func applyActivePanel(_ panel: SidebarPanel) {
        activePanel = panel

        // Scroll view visibility
        let isGitTab = panel == .git
        fileTreeScrollView.isHidden = isGitTab
        gitScrollView.isHidden = !isGitTab

        // Activity bar highlight
        activityBar.setActivePanel(panel)

        // Panel header
        panelHeader.setPanel(panel)
        panelHeader.updateHiddenFilesIcon(showing: showsHiddenFiles)

        // Git auto-refresh
        if isGitTab {
            gitAutoRefreshMonitor.requestVisibleRefreshIfNeeded()
        }
    }

    // MARK: - Actions

    @objc private func toggleShowHiddenFiles(_ sender: Any?) {
        showsHiddenFiles.toggle()
        UserDefaults.standard.set(showsHiddenFiles, forKey: "sidebarShowHiddenFiles")
        panelHeader.updateHiddenFilesIcon(showing: showsHiddenFiles)
        reloadFileTree()
    }

    @objc private func openFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder to open in the sidebar"

        guard let window = view.window else {
            if panel.runModal() == .OK, let url = panel.url {
                setRootDirectory(url)
            }
            return
        }

        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.setRootDirectory(url)
            }
        }
    }

    @objc private func refreshTree(_ sender: Any?) {
        guard let url = rootURL else { return }
        if activePanel == .git {
            gitAutoRefreshMonitor.requestImmediateRefresh(.manual)
        } else {
            setRootDirectory(url)
        }
    }

    private func reloadFileTree() {
        guard let url = rootURL else { return }
        setRootDirectory(url)
    }

    @objc private func outlineViewClicked(_ sender: Any?) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0,
              let node = outlineView.item(atRow: clickedRow) as? FileNode,
              !node.isDirectory else { return }

        NotificationCenter.default.post(
            name: .sidebarOpenFilePreview,
            object: nil,
            userInfo: ["url": node.url]
        )
    }

    @objc private func outlineViewDoubleClicked(_ sender: Any?) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0,
              let node = outlineView.item(atRow: clickedRow) as? FileNode else { return }

        if node.isDirectory {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
        }
    }

    @objc private func gitChangesTableClicked(_ sender: Any?) {
        let row = gitChangesTable.clickedRow
        guard row >= 0, row < gitRows.count else { return }

        if case .changedFile(let path, _, let repoURL) = gitRows[row] {
            NotificationCenter.default.post(
                name: .sidebarOpenDiff,
                object: nil,
                userInfo: ["filePath": path, "repoURL": repoURL]
            )
        }
    }

    // MARK: - Git Status

    private func performGitStatusRefresh(trigger _: GitAutoRefreshMonitor.Trigger) {
        guard let rootURL, let rootNode else {
            cachedGitStatuses = [:]
            discoveredRepos = []
            updateGitPanel(repos: [])
            gitAutoRefreshMonitor.refreshDidFinish()
            return
        }

        let generation = gitStatusGeneration
        DispatchQueue.global(qos: .userInitiated).async {
            let repos = GitStatusProvider.discoverGitRepos(under: rootURL)
            var mergedStatuses: [String: FileNode.GitStatus] = [:]
            for repo in repos {
                if repo.url == rootURL {
                    mergedStatuses.merge(repo.statuses) { _, new in new }
                } else {
                    let prefix = repo.url.lastPathComponent
                    for (path, status) in repo.statuses {
                        mergedStatuses[prefix + "/" + path] = status
                    }
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                defer { self.gitAutoRefreshMonitor.refreshDidFinish() }
                guard self.gitStatusGeneration == generation else { return }

                self.cachedGitStatuses = mergedStatuses
                self.discoveredRepos = repos
                GitStatusProvider.applyStatuses(mergedStatuses, to: rootNode, rootURL: rootURL)
                self.outlineView.reloadData()
                if let root = self.rootNode {
                    self.outlineView.expandItem(root)
                }
                self.updateGitPanel(repos: repos)
            }
        }
    }

    private func updateGitPanel(repos: [GitStatusProvider.RepoInfo]) {
        var rows: [GitRow] = []
        for repo in repos {
            let repoName = repo.url.lastPathComponent
            rows.append(.repoHeader(
                name: repoName,
                branch: repo.branch,
                changeCount: repo.statuses.count
            ))

            let sortedFiles = repo.statuses
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            for (path, status) in sortedFiles {
                rows.append(.changedFile(path: path, status: status, repoURL: repo.url))
            }
        }
        gitRows = rows

        // Update badge on activity bar
        let totalChanges = repos.reduce(0) { $0 + $1.statuses.count }
        activityBar.setBadge(totalChanges, for: .git)

        gitChangesTable.reloadData()
    }

    // MARK: - Cell Factories

    private func makeFileTreeCell(for node: FileNode) -> NSView {
        let cellID = NSUserInterfaceItemIdentifier("FileTreeCell")
        let cell: NSTableCellView

        if let reused = outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown
            cell.addSubview(imageView)
            cell.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.font = sidebarUIFont(ofSize: 13)
            cell.addSubview(textField)
            cell.textField = textField

            let badge = NSTextField(labelWithString: "")
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.font = sidebarUIMonoFont(ofSize: 11, weight: .bold)
            badge.alignment = .center
            badge.tag = 100
            cell.addSubview(badge)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                badge.leadingAnchor.constraint(greaterThanOrEqualTo: textField.trailingAnchor, constant: 4),
                badge.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
            ])
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        cell.textField?.stringValue = node.name
        cell.textField?.textColor = node.gitStatus.color
        cell.imageView?.image = fileIcon(for: node)

        if let badge = cell.viewWithTag(100) as? NSTextField {
            badge.stringValue = node.gitStatus.indicator
            badge.textColor = node.gitStatus.color
        }

        return cell
    }

    private func makeGitChangeCell(for entry: (path: String, status: FileNode.GitStatus, repoURL: URL),
                                   in tableView: NSTableView) -> NSView {
        let cellID = NSUserInterfaceItemIdentifier("GitChangeCell")
        let cell: NSTableCellView

        if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID

            let badge = NSTextField(labelWithString: "")
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.font = sidebarUIMonoFont(ofSize: 11, weight: .bold)
            badge.alignment = .center
            badge.tag = 200
            cell.addSubview(badge)

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingHead
            textField.font = sidebarUIFont(ofSize: 13)
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 22),
                badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                badge.widthAnchor.constraint(equalToConstant: 14),
                textField.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let fileName = (entry.path as NSString).lastPathComponent
        cell.textField?.stringValue = fileName
        cell.textField?.textColor = entry.status.color
        cell.textField?.toolTip = entry.path

        if let badge = cell.viewWithTag(200) as? NSTextField {
            badge.stringValue = entry.status.indicator
            badge.textColor = entry.status.color
        }

        return cell
    }

    private func makeRepoHeaderCell(name: String, branch: String, changeCount: Int,
                                    in tableView: NSTableView) -> NSView {
        let cellID = NSUserInterfaceItemIdentifier("RepoHeaderCell")
        let cell: NSTableCellView

        if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID

            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.imageScaling = .scaleProportionallyDown
            icon.tag = 301
            cell.addSubview(icon)

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = sidebarUIFont(ofSize: 13, weight: .semibold)
            textField.lineBreakMode = .byTruncatingTail
            cell.addSubview(textField)
            cell.textField = textField

            let countLabel = NSTextField(labelWithString: "")
            countLabel.translatesAutoresizingMaskIntoConstraints = false
            countLabel.font = sidebarUIMonoFont(ofSize: 11, weight: .medium)
            countLabel.alignment = .center
            countLabel.tag = 302
            cell.addSubview(countLabel)

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 14),
                icon.heightAnchor.constraint(equalToConstant: 14),
                textField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textField.trailingAnchor, constant: 4),
                countLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                countLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        cell.textField?.stringValue = "\(name)  ⎇ \(branch)"
        cell.textField?.textColor = .labelColor

        if let icon = cell.viewWithTag(301) as? NSImageView {
            icon.image = NSImage(systemSymbolName: "arrow.triangle.branch",
                                 accessibilityDescription: "Git repo")
            icon.contentTintColor = .secondaryLabelColor
        }

        if let countLabel = cell.viewWithTag(302) as? NSTextField {
            if changeCount > 0 {
                countLabel.stringValue = "\(changeCount)"
                countLabel.textColor = FileNode.GitStatus.modified.color
            } else {
                countLabel.stringValue = "✓"
                countLabel.textColor = NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? NSColor.systemGreen
                        : NSColor(red: 0.15, green: 0.55, blue: 0.20, alpha: 1.0)
                }
            }
        }

        return cell
    }

    private func fileIcon(for node: FileNode) -> NSImage {
        if node.isDirectory {
            return NSImage(systemSymbolName: "folder.fill",
                           accessibilityDescription: "Folder")
                ?? NSWorkspace.shared.icon(for: .folder)
        }
        return NSWorkspace.shared.icon(forFile: node.url.path)
    }
}

// MARK: - ActivityBarDelegate

extension SidebarViewController: ActivityBarDelegate {
    fileprivate func activityBar(_ bar: ActivityBarView, didSelectPanel panel: SidebarPanel) {
        applyActivePanel(panel)
    }
}

// MARK: - NSOutlineViewDataSource

extension SidebarViewController: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView,
                     numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return rootNode?.children?.count ?? 0
        }
        guard let node = item as? FileNode else { return 0 }
        return node.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView,
                     child index: Int,
                     ofItem item: Any?) -> Any {
        if item == nil {
            guard let children = rootNode?.children, index < children.count else {
                return FileNode(url: URL(fileURLWithPath: "/"))
            }
            return children[index]
        }
        guard let node = item as? FileNode,
              let children = node.children, index < children.count else {
            return FileNode(url: URL(fileURLWithPath: "/"))
        }
        return children[index]
    }

    func outlineView(_ outlineView: NSOutlineView,
                     isItemExpandable item: Any) -> Bool {
        guard let node = item as? FileNode else { return false }
        return node.isDirectory
    }
}

// MARK: - NSOutlineViewDelegate

extension SidebarViewController: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        return makeFileTreeCell(for: node)
    }

    func outlineView(_ outlineView: NSOutlineView,
                     heightOfRowByItem item: Any) -> CGFloat {
        return 22
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
        if !node.isLoaded {
            node.loadChildren(showHiddenFiles: showsHiddenFiles)
            if let rootURL, !cachedGitStatuses.isEmpty {
                GitStatusProvider.applyStatuses(cachedGitStatuses, to: node, rootURL: rootURL)
            }
        }
    }
}

// MARK: - NSTableViewDataSource + Delegate (Git Changes Table)

extension SidebarViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        guard tableView === gitChangesTable else { return 0 }
        return gitRows.count
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard tableView === gitChangesTable, row < gitRows.count else { return nil }

        switch gitRows[row] {
        case .repoHeader(let name, let branch, let count):
            return makeRepoHeaderCell(name: name, branch: branch, changeCount: count, in: tableView)
        case .changedFile(let path, let status, let repoURL):
            return makeGitChangeCell(for: (path: path, status: status, repoURL: repoURL), in: tableView)
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard tableView === gitChangesTable, row < gitRows.count else { return 20 }
        switch gitRows[row] {
        case .repoHeader: return 22
        case .changedFile: return 20
        }
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        return false
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let sidebarOpenFilePreview = Notification.Name("sidebarOpenFilePreview")
    static let sidebarOpenDiff = Notification.Name("sidebarOpenDiff")
    static let terminalSurfaceDidFocus = Notification.Name("terminalSurfaceDidFocus")
}
