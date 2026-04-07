import AppKit
import UniformTypeIdentifiers

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
    private var activeTint = NSColor.controlAccentColor
    private var inactiveTint = NSColor.secondaryLabelColor
    private var badgeBackground = NSColor.controlAccentColor
    private var badgeForeground = NSColor.white
    private var separatorColor = NSColor.separatorColor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

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
            badge.textColor = badgeForeground
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
            badge.textColor = badgeForeground
            badge.layer?.backgroundColor = badgeBackground.cgColor
        } else {
            badge.isHidden = true
        }
    }

    func applyTheme() {
        let theme = SpectraThemeManager.shared
        activeTint = theme.color(.activityBarForeground)
        inactiveTint = theme.color(.activityBarInactiveForeground)
        badgeBackground = theme.color(.activityBarBadgeBackground)
        badgeForeground = theme.color(.activityBarBadgeForeground)
        separatorColor = theme.color(.separator)
        layer?.backgroundColor = theme.color(.activityBarBackground).cgColor
        for badge in badges.values where !badge.isHidden {
            badge.textColor = badgeForeground
            badge.layer?.backgroundColor = badgeBackground.cgColor
        }
        updateHighlight()
        needsDisplay = true
    }

    private func updateHighlight() {
        for panel in SidebarPanel.allCases {
            let isActive = panel == currentPanel
            buttons[panel]?.contentTintColor = isActive ? activeTint : inactiveTint
            buttons[panel]?.setAccessibilityValue(isActive ? "1" : "0")
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 1px separator on the right edge
        separatorColor.setFill()
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
        wantsLayer = true

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

    func applyTheme() {
        let theme = SpectraThemeManager.shared
        titleLabel.textColor = theme.color(.sidebarSecondaryForeground)
        rootLabel.textColor = theme.color(.sidebarTertiaryForeground)
        layer?.backgroundColor = theme.color(.sidebarBackground).cgColor
        for button in [openFolderButton, showHiddenFilesButton, refreshButton] {
            button.contentTintColor = theme.color(.sidebarSecondaryForeground)
        }
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
class SidebarViewController: NSViewController, NSMenuDelegate {

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
    private var themeObserver: NSObjectProtocol?
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

    // MARK: - Context Menu
    private var contextMenu: NSMenu!

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
        applyTheme()
        themeObserver = NotificationCenter.default.addObserver(
            forName: .spectraThemeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyTheme()
        }
    }

    deinit {
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
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
        outlineView.allowsMultipleSelection = true

        let column = NSTableColumn(identifier: fileColumnID)
        column.title = "Name"
        column.minWidth = 50
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.doubleAction = #selector(outlineViewDoubleClicked(_:))
        outlineView.target = self

        // Context menu
        contextMenu = NSMenu()
        contextMenu.delegate = self
        contextMenu.autoenablesItems = false
        outlineView.menu = contextMenu

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

    var selectedFileNodes: [FileNode] {
        guard let outlineView = outlineView else { return [] }
        return outlineView.selectedRowIndexes.compactMap { rowIndex in
            outlineView.item(atRow: rowIndex) as? FileNode
        }
    }

    // MARK: - Panel Switching (centralized)

    private func applyTheme() {
        activityBar.applyTheme()
        panelHeader.applyTheme()
        outlineView?.reloadData()
        gitChangesTable?.reloadData()
    }

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

    // MARK: - Preview Helper

    private func requestPreview(for url: URL) {
        NotificationCenter.default.post(
            name: .sidebarOpenFilePreview,
            object: nil,
            userInfo: ["url": url]
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
                if let root = self.rootNode {
                    self.outlineView.reloadItem(root, reloadChildren: true)
                } else {
                    self.outlineView.reloadData()
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
        cell.textField?.textColor = SpectraThemeManager.shared.color(.sidebarForeground)

        if let icon = cell.viewWithTag(301) as? NSImageView {
            icon.image = NSImage(systemSymbolName: "arrow.triangle.branch",
                                 accessibilityDescription: "Git repo")
            icon.contentTintColor = SpectraThemeManager.shared.color(.sidebarSecondaryForeground)
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

// MARK: - NSMenuDelegate

extension SidebarViewController {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let clickedRow = outlineView.clickedRow

        // Handle empty space click (clickedRow == -1)
        if clickedRow == -1 {
            // Show only "Open in Finder" pointing to root directory
            let openInFinderItem = NSMenuItem(
                title: "Open in Finder",
                action: #selector(openRootInFinder(_:)),
                keyEquivalent: ""
            )
            openInFinderItem.target = self
            openInFinderItem.toolTip = "Open root directory in Finder"
            menu.addItem(openInFinderItem)
            return
        }

        // Sync clickedRow with selection if not already selected
        if clickedRow >= 0, !outlineView.selectedRowIndexes.contains(clickedRow) {
            outlineView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }

        // Get selected nodes
        let selectedNodes = selectedFileNodes
        guard !selectedNodes.isEmpty else { return }

        // Check selection type for menu item enabling
        let isSingleSelection = selectedNodes.count == 1
        let isSingleFile = isSingleSelection && !selectedNodes[0].isDirectory
        let allAreFiles = selectedNodes.allSatisfy { !$0.isDirectory }

        // 1. Preview (enabled for single file only)
        let previewItem = NSMenuItem(
            title: "Preview",
            action: #selector(openPreview(_:)),
            keyEquivalent: ""
        )
        previewItem.target = self
        previewItem.toolTip = "Preview file content"
        previewItem.isEnabled = isSingleFile
        if isSingleFile {
            previewItem.representedObject = selectedNodes[0].url
        }
        menu.addItem(previewItem)

        // Separator between in-app and external actions
        menu.addItem(NSMenuItem.separator())

        // 2. Open in Finder
        let openInFinderItem = NSMenuItem(
            title: isSingleSelection ? "Open in Finder" : "Open \(selectedNodes.count) items in Finder",
            action: #selector(openSelectedInFinder(_:)),
            keyEquivalent: ""
        )
        openInFinderItem.target = self
        openInFinderItem.toolTip = "Show selected items in Finder"
        openInFinderItem.isEnabled = true
        openInFinderItem.representedObject = selectedNodes.compactMap { $0.url }
        menu.addItem(openInFinderItem)

        // 3. Open With...
        let openWithItem = NSMenuItem(
            title: "Open With...",
            action: nil,
            keyEquivalent: ""
        )
        openWithItem.toolTip = "Open with another application"
        openWithItem.isEnabled = allAreFiles
        if allAreFiles {
            let submenu = buildOpenWithSubmenu(for: selectedNodes)
            openWithItem.submenu = submenu
        }
        menu.addItem(openWithItem)

        // 4. Send Copy To...
        let sendCopyItem = NSMenuItem(
            title: "Send Copy To...",
            action: #selector(showSendCopyDialog(_:)),
            keyEquivalent: ""
        )
        sendCopyItem.target = self
        sendCopyItem.toolTip = "Copy selected items to another location"
        sendCopyItem.isEnabled = true
        sendCopyItem.representedObject = selectedNodes
        menu.addItem(sendCopyItem)
    }

    // MARK: - Context Menu Actions

    @objc private func openPreview(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem,
              let url = menuItem.representedObject as? URL else { return }
        requestPreview(for: url)
    }

    @objc private func openRootInFinder(_ sender: Any?) {
        guard let rootURL = rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([rootURL])
    }

    @objc private func openSelectedInFinder(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem,
              let urls = menuItem.representedObject as? [URL],
              !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc private func showSendCopyDialog(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem,
              let selectedNodes = menuItem.representedObject as? [FileNode],
              !selectedNodes.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Copy Here"
        panel.message = "Choose destination folder for copy"
        panel.title = "Send Copy To"

        guard let window = view.window else {
            if panel.runModal() == .OK, let destURL = panel.url {
                performCopy(selectedNodes: selectedNodes, to: destURL)
            }
            return
        }

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destURL = panel.url else { return }
            self?.performCopy(selectedNodes: selectedNodes, to: destURL)
        }
    }

    // MARK: - Open With Helper

    private func buildOpenWithSubmenu(for nodes: [FileNode]) -> NSMenu {
        let submenu = NSMenu()
        submenu.title = "" // Prevent grey header text

        let urls = nodes.compactMap { $0.url }
        guard !urls.isEmpty else {
            addOtherAppItem(to: submenu, fileURLs: urls)
            return submenu
        }

        // Find apps that can open all selected files
        var commonAppURLs: [URL]?
        for url in urls {
            let appsForFile = NSWorkspace.shared.urlsForApplications(toOpen: url)
            if commonAppURLs == nil {
                commonAppURLs = appsForFile
            } else {
                commonAppURLs = commonAppURLs?.filter { appsForFile.contains($0) }
            }
        }

        let appURLs = commonAppURLs ?? []

        // Determine default app (only mark if all files share the same default)
        var defaultAppURL: URL?
        let firstDefault = NSWorkspace.shared.urlForApplication(toOpen: urls[0])
        if urls.count == 1 {
            defaultAppURL = firstDefault
        } else if let first = firstDefault {
            let allSameDefault = urls.dropFirst().allSatisfy { url in
                NSWorkspace.shared.urlForApplication(toOpen: url) == first
            }
            defaultAppURL = allSameDefault ? first : nil
        }

        struct AppInfo {
            let url: URL
            let displayName: String
            let isDefault: Bool
        }

        // Resolve display names with Bundle cached per app
        let bundledApps: [(URL, Bundle?, String)] = appURLs.map { appURL in
            let bundle = Bundle(url: appURL)
            let localized = bundle?.localizedInfoDictionary
            let info = bundle?.infoDictionary
            let name = (localized?["CFBundleDisplayName"] as? String)
                ?? (info?["CFBundleDisplayName"] as? String)
                ?? (info?["CFBundleName"] as? String)
                ?? appURL.lastPathComponent
            return (appURL, bundle, name)
        }

        // Disambiguate duplicate names with version, then path
        var nameCount: [String: Int] = [:]
        for (_, _, name) in bundledApps { nameCount[name, default: 0] += 1 }

        var appInfos: [AppInfo] = bundledApps.map { (appURL, bundle, name) in
            var displayName = name
            if nameCount[name, default: 0] > 1 {
                if let version = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String {
                    displayName = "\(name) (\(version))"
                } else {
                    let parent = appURL.deletingLastPathComponent().lastPathComponent
                    displayName = "\(name) — \(parent)"
                }
            }
            let isDefault = (defaultAppURL != nil && appURL == defaultAppURL)
            return AppInfo(url: appURL, displayName: displayName, isDefault: isDefault)
        }

        // Sort: default first, then alphabetically
        appInfos.sort { a, b in
            if a.isDefault != b.isDefault { return a.isDefault }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }

        // Add menu items
        let iconSize = NSSize(width: 16, height: 16)
        for (index, info) in appInfos.enumerated() {
            let title = info.isDefault ? "\(info.displayName) (預設)" : info.displayName
            let item = NSMenuItem(title: title, action: #selector(openWithApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["appURL": info.url, "fileURLs": urls]

            let icon = NSWorkspace.shared.icon(forFile: info.url.path).copy() as! NSImage
            icon.size = iconSize
            item.image = icon

            submenu.addItem(item)

            // Separator after default app
            if info.isDefault && index < appInfos.count - 1 {
                submenu.addItem(NSMenuItem.separator())
            }
        }

        // "Other..." option
        if !appInfos.isEmpty {
            submenu.addItem(NSMenuItem.separator())
        }
        addOtherAppItem(to: submenu, fileURLs: urls)

        return submenu
    }

    private func addOtherAppItem(to menu: NSMenu, fileURLs: [URL]) {
        let otherItem = NSMenuItem(title: "其他...", action: #selector(openWithOther(_:)), keyEquivalent: "")
        otherItem.target = self
        otherItem.representedObject = fileURLs
        menu.addItem(otherItem)
    }

    @objc private func openWithOther(_ sender: NSMenuItem) {
        guard let fileURLs = sender.representedObject as? [URL], !fileURLs.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Open"
        panel.message = "Choose an application"

        let handler = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let appURL = panel.url else { return }
            let config = NSWorkspace.OpenConfiguration()
            for fileURL in fileURLs {
                NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config, completionHandler: nil)
            }
        }

        guard let window = view.window else {
            let response = panel.runModal()
            handler(response)
            return
        }
        panel.beginSheetModal(for: window, completionHandler: handler)
    }

    @objc private func openWithApp(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let appURL = info["appURL"] as? URL,
              let fileURLs = info["fileURLs"] as? [URL] else { return }

        // Open each file with the selected app
        let config = NSWorkspace.OpenConfiguration()
        for fileURL in fileURLs {
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config, completionHandler: nil)
        }
    }

    // MARK: - Copy Helper

    private func performCopy(selectedNodes: [FileNode], to destination: URL) {
        let fileManager = FileManager.default

        // Filter out same-directory copies and destination-inside-source (would recurse)
        let destStd = destination.standardizedFileURL.path
        let validNodes = selectedNodes.filter { node in
            let srcDir = node.url.deletingLastPathComponent().standardizedFileURL.path
            if srcDir == destStd { return false }
            // Reject copying a directory into itself or its descendants
            if node.isDirectory {
                let srcStd = node.url.standardizedFileURL.path
                if destStd.hasPrefix(srcStd + "/") || destStd == srcStd { return false }
            }
            return true
        }
        guard !validNodes.isEmpty else { return }

        // Classify: conflicts vs safe
        var conflicts: [FileNode] = []
        var safe: [FileNode] = []
        var skippedDirs: [String] = []
        for node in validNodes {
            let destURL = destination.appendingPathComponent(node.url.lastPathComponent)
            if fileManager.fileExists(atPath: destURL.path) {
                if node.isDirectory {
                    skippedDirs.append(node.url.lastPathComponent)
                    continue
                }
                conflicts.append(node)
            } else {
                safe.append(node)
            }
        }

        if conflicts.isEmpty {
            executeCopy(nodes: safe, overwriteNodes: [], skippedDirs: skippedDirs, to: destination)
            return
        }

        // Show conflict resolution dialog
        let alert = NSAlert()
        alert.messageText = "目標位置已有同名檔案"
        let conflictNames = conflicts.map { $0.url.lastPathComponent }.joined(separator: "\n")
        alert.informativeText = "以下 \(conflicts.count) 個檔案已存在：\n\(conflictNames)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "覆蓋全部")
        alert.addButton(withTitle: "跳過已存在")
        alert.addButton(withTitle: "取消")
        alert.buttons[0].hasDestructiveAction = true

        let handler = { [weak self] (response: NSApplication.ModalResponse) in
            switch response {
            case .alertFirstButtonReturn:
                self?.executeCopy(nodes: safe, overwriteNodes: conflicts, skippedDirs: skippedDirs, to: destination)
            case .alertSecondButtonReturn:
                self?.executeCopy(nodes: safe, overwriteNodes: [], skippedDirs: skippedDirs, to: destination)
            default:
                break
            }
        }

        guard let window = view.window else {
            let response = alert.runModal()
            handler(response)
            return
        }
        alert.beginSheetModal(for: window, completionHandler: handler)
    }

    private func executeCopy(nodes: [FileNode], overwriteNodes: [FileNode], skippedDirs: [String], to destination: URL) {
        let fileManager = FileManager.default
        var errors: [(String, String)] = []

        let allNodes: [(node: FileNode, overwrite: Bool)] =
            overwriteNodes.map { ($0, true) } + nodes.map { ($0, false) }

        for (node, overwrite) in allNodes {
            let sourceURL = node.url
            let destURL = destination.appendingPathComponent(sourceURL.lastPathComponent)
            do {
                if overwrite {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.copyItem(at: sourceURL, to: destURL)
            } catch {
                errors.append((sourceURL.lastPathComponent, error.localizedDescription))
            }
        }

        // Report skipped directories and IO errors
        var messages: [String] = []
        if !skippedDirs.isEmpty {
            messages.append("已跳過同名目錄：\n" + skippedDirs.joined(separator: "\n"))
        }
        if !errors.isEmpty {
            messages.append("複製失敗：\n" + errors.map { "\($0.0): \($0.1)" }.joined(separator: "\n"))
        }
        if !messages.isEmpty {
            showErrorAlert(
                title: errors.isEmpty ? "部分項目已跳過" : "部分檔案複製失敗",
                message: messages.joined(separator: "\n\n")
            )
        }
    }

    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        guard let window = view.window else {
            alert.runModal()
            return
        }
        alert.beginSheetModal(for: window)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let sidebarOpenFilePreview = Notification.Name("sidebarOpenFilePreview")
    static let sidebarOpenDiff = Notification.Name("sidebarOpenDiff")
    static let terminalSurfaceDidFocus = Notification.Name("terminalSurfaceDidFocus")
}
