import AppKit

/// Sidebar with two full-height panels: File Explorer and Source Control.
/// Switched via a segmented tab bar in the header.
class SidebarViewController: NSViewController {

    // MARK: - UI Font

    /// Preferred UI font with CJK support, falling back to system font.
    private static func uiFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let psName: String
        switch weight {
        case .semibold, .bold, .medium: psName = "Sarasa-UI-TC-SemiBold"
        case .light:                    psName = "Sarasa-UI-TC-Light"
        default:               psName = "Sarasa-UI-TC-Regular"
        }
        return NSFont(name: psName, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    private static func uiMonoFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let psName = weight == .bold || weight == .semibold
            ? "Sarasa-Mono-TC-SemiBold" : "Sarasa-Mono-TC-Regular"
        return NSFont(name: psName, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    // MARK: - Tab bar
    private var tabBar: NSSegmentedControl!
    private var openFolderButton: NSButton!
    private var showHiddenFilesButton: NSButton!
    private var refreshButton: NSButton!
    private var headerView: NSView!
    private var rootLabel: NSTextField!

    // MARK: - File Tree
    private var outlineView: NSOutlineView!
    private var fileTreeScrollView: NSScrollView!

    // MARK: - Source Control (full height)
    private var gitInfoLabel: NSTextField!
    private var gitChangesTable: NSTableView!
    private var gitScrollView: NSScrollView!

    // MARK: - State
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

        buildHeader()
        buildFileTree()
        buildGitPanel()

        container.addSubview(headerView)
        container.addSubview(fileTreeScrollView)
        container.addSubview(gitScrollView)

        let safeArea = container.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            // Header (tab bar + buttons)
            headerView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // File tree — full height below header
            fileTreeScrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            fileTreeScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            fileTreeScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            fileTreeScrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // Git panel — full height below header (same position, toggled via isHidden)
            gitScrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            gitScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gitScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            gitScrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Start on Files tab
        gitScrollView.isHidden = true

        self.view = container
    }

    // MARK: - Build Header (tab bar + action buttons)

    private func buildHeader() {
        headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false

        // Segmented tab bar
        tabBar = NSSegmentedControl(labels: ["Files", "Git"], trackingMode: .selectOne, target: self, action: #selector(tabChanged(_:)))
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.selectedSegment = 0
        tabBar.segmentStyle = .capsule
        tabBar.controlSize = .small
        // Set SF Symbol images
        tabBar.setImage(NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Files"), forSegment: 0)
        tabBar.setImage(NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Git"), forSegment: 1)
        tabBar.setWidth(0, forSegment: 0) // auto-size
        tabBar.setWidth(0, forSegment: 1)

        // Folder name label (shows below tab bar area, reuses rootLabel)
        rootLabel = NSTextField(labelWithString: "No Folder Open")
        rootLabel.translatesAutoresizingMaskIntoConstraints = false
        rootLabel.font = Self.uiFont(ofSize: 11, weight: .medium)
        rootLabel.textColor = .tertiaryLabelColor
        rootLabel.lineBreakMode = .byTruncatingMiddle
        rootLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        openFolderButton = NSButton(
            image: NSImage(systemSymbolName: "folder.badge.plus",
                           accessibilityDescription: "Open Folder")!,
            target: self,
            action: #selector(openFolder(_:))
        )
        openFolderButton.translatesAutoresizingMaskIntoConstraints = false
        openFolderButton.bezelStyle = .accessoryBarAction
        openFolderButton.toolTip = "Open Folder"
        openFolderButton.controlSize = .small

        showHiddenFilesButton = NSButton(
            image: NSImage(systemSymbolName: "eye.slash",
                           accessibilityDescription: "Show Hidden Files")!,
            target: self,
            action: #selector(toggleShowHiddenFiles(_:))
        )
        showHiddenFilesButton.translatesAutoresizingMaskIntoConstraints = false
        showHiddenFilesButton.bezelStyle = .accessoryBarAction
        showHiddenFilesButton.controlSize = .small

        refreshButton = NSButton(
            image: NSImage(systemSymbolName: "arrow.clockwise",
                           accessibilityDescription: "Refresh")!,
            target: self,
            action: #selector(refreshTree(_:))
        )
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.bezelStyle = .accessoryBarAction
        refreshButton.toolTip = "Refresh"
        refreshButton.controlSize = .small

        headerView.addSubview(tabBar)
        headerView.addSubview(rootLabel)
        headerView.addSubview(openFolderButton)
        headerView.addSubview(showHiddenFilesButton)
        headerView.addSubview(refreshButton)

        updateShowHiddenFilesButton()

        NSLayoutConstraint.activate([
            headerView.heightAnchor.constraint(equalToConstant: 48),

            // Tab bar centered horizontally, near top
            tabBar.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 4),
            tabBar.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 6),

            // Action buttons right-aligned, same line as tabs
            refreshButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -4),
            refreshButton.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            showHiddenFilesButton.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -2),
            showHiddenFilesButton.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            openFolderButton.trailingAnchor.constraint(equalTo: showHiddenFilesButton.leadingAnchor, constant: -2),
            openFolderButton.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),

            // Root label below tab bar
            rootLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            rootLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -2),
            rootLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -8),
        ])
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
        rootLabel.stringValue = url.lastPathComponent
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

    // MARK: - Tab Switching

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        let isGitTab = sender.selectedSegment == 1
        fileTreeScrollView.isHidden = isGitTab
        gitScrollView.isHidden = !isGitTab
        updateShowHiddenFilesButton()
        if isGitTab {
            gitAutoRefreshMonitor.requestVisibleRefreshIfNeeded()
        }
    }

    // MARK: - Actions

    @objc private func toggleShowHiddenFiles(_ sender: Any?) {
        showsHiddenFiles.toggle()
        UserDefaults.standard.set(showsHiddenFiles, forKey: "sidebarShowHiddenFiles")
        updateShowHiddenFilesButton()
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
        if tabBar.selectedSegment == 1 {
            gitAutoRefreshMonitor.requestImmediateRefresh(.manual)
        } else {
            setRootDirectory(url)
        }
    }

    private func reloadFileTree() {
        guard let url = rootURL else { return }
        setRootDirectory(url)
    }

    private func updateShowHiddenFilesButton() {
        let isFilesTab = tabBar?.selectedSegment != 1
        let symbolName = showsHiddenFiles ? "eye" : "eye.slash"
        let accessibilityDescription = showsHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files"
        showHiddenFilesButton?.image = NSImage(systemSymbolName: symbolName,
                                               accessibilityDescription: accessibilityDescription)
        showHiddenFilesButton?.toolTip = showsHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files"
        showHiddenFilesButton?.isEnabled = isFilesTab
        showHiddenFilesButton?.alphaValue = isFilesTab ? 1.0 : 0.5
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

        // Update tab badge: show change count on Git tab
        let totalChanges = repos.reduce(0) { $0 + $1.statuses.count }
        if totalChanges > 0 {
            tabBar.setLabel("Git (\(totalChanges))", forSegment: 1)
        } else {
            tabBar.setLabel("Git", forSegment: 1)
        }

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
            textField.font = Self.uiFont(ofSize: 13)
            cell.addSubview(textField)
            cell.textField = textField

            let badge = NSTextField(labelWithString: "")
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.font = Self.uiMonoFont(ofSize: 11, weight: .bold)
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
            badge.font = Self.uiMonoFont(ofSize: 11, weight: .bold)
            badge.alignment = .center
            badge.tag = 200
            cell.addSubview(badge)

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingHead
            textField.font = Self.uiFont(ofSize: 13)
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
            textField.font = Self.uiFont(ofSize: 13, weight: .semibold)
            textField.lineBreakMode = .byTruncatingTail
            cell.addSubview(textField)
            cell.textField = textField

            let countLabel = NSTextField(labelWithString: "")
            countLabel.translatesAutoresizingMaskIntoConstraints = false
            countLabel.font = Self.uiMonoFont(ofSize: 11, weight: .medium)
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
