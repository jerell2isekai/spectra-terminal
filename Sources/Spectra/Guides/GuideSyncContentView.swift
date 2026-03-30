import AppKit
import WebKit

final class GuideSyncContentView: NSView, WKNavigationDelegate, NSTextViewDelegate {
    private let store: GuideSyncStore
    private let service: GuideSyncService
    private let currentProjectPathProvider: () -> String?

    private var targets: [GuideSyncTarget] = [] {
        didSet {
            renderTargets()
            updateActionButtonStates()
        }
    }

    private var selectedGuide: GuideTemplateKind = .agents
    private var savedTemplateMarkdown: String = ""
    private var previewMarkdown: String = ""
    private var hasUnsavedChanges: Bool {
        previewMarkdown != savedTemplateMarkdown
    }
    private var isRenderedMode = true {
        didSet { applyPreviewMode() }
    }
    private var isSyncing = false {
        didSet { updateActionButtonStates() }
    }

    private let toolbarStack = NSStackView()
    private let guideSelector: NSSegmentedControl
    private let modeControl = NSSegmentedControl(labels: ["Raw", "Preview"], trackingMode: .selectOne, target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)

    private let targetsStack = NSStackView()
    private let targetsDocumentView = FlippedView()
    private let targetsScrollView = NSScrollView()

    private let previewContainer = NSView()
    private let previewScrollView = NSScrollView()
    private let previewTextView = NSTextView()
    private var previewWebView: WKWebView?

    private let resultTextView = NSTextView()
    private let previewTitleLabel = NSTextField(labelWithString: "")

    private let addTargetButton = NSButton(title: "Add Target…", target: nil, action: nil)
    private let addCurrentProjectButton = NSButton(title: "Add Current Project", target: nil, action: nil)
    private let syncCurrentProjectButton = NSButton(title: "Sync Current Project", target: nil, action: nil)
    private let syncAllEnabledButton = NSButton(title: "Sync All Enabled", target: nil, action: nil)

    init(store: GuideSyncStore = .shared,
         service: GuideSyncService = .shared,
         currentProjectPathProvider: @escaping () -> String?) {
        self.store = store
        self.service = service
        self.currentProjectPathProvider = currentProjectPathProvider
        self.guideSelector = NSSegmentedControl(
            labels: service.templateKinds.map(\.fileName),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        super.init(frame: .zero)

        guideSelector.target = self
        guideSelector.action = #selector(guideSelectionChanged(_:))
        guideSelector.selectedSegment = 0
        guideSelector.segmentStyle = .capsule

        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        modeControl.selectedSegment = 1
        modeControl.segmentStyle = .capsule

        saveButton.target = self
        saveButton.action = #selector(saveCurrentTemplate(_:))
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .regular

        addTargetButton.target = self
        addTargetButton.action = #selector(addTarget(_:))
        addCurrentProjectButton.target = self
        addCurrentProjectButton.action = #selector(addCurrentProject(_:))
        syncCurrentProjectButton.target = self
        syncCurrentProjectButton.action = #selector(syncCurrentProject(_:))
        syncAllEnabledButton.target = self
        syncAllEnabledButton.action = #selector(syncAllEnabled(_:))

        configureButtons()
        setupToolbar()
        setupLayout()
        loadTargets()
        refreshPreview()
        showStatus("Ready. Sync will write the managed AGENTS.md and CLAUDE.md templates into explicitly selected project roots.", isError: false)
        updateActionButtonStates()
    }

    required init?(coder: NSCoder) { fatalError() }

    var headerToolbar: NSView { toolbarStack }

    override func layout() {
        super.layout()
        layoutTargetsDocumentView()
    }

    // MARK: - Setup

    private func configureButtons() {
        for button in [addTargetButton, addCurrentProjectButton, syncCurrentProjectButton, syncAllEnabledButton] {
            button.bezelStyle = .rounded
            button.controlSize = .regular
        }
    }

    private func setupToolbar() {
        toolbarStack.orientation = .horizontal
        toolbarStack.alignment = .centerY
        toolbarStack.spacing = 8
        toolbarStack.addArrangedSubview(guideSelector)
        toolbarStack.addArrangedSubview(modeControl)
        toolbarStack.addArrangedSubview(saveButton)
    }

    private func setupLayout() {
        let mainStack = NSStackView()
        mainStack.orientation = .horizontal
        mainStack.spacing = 0
        mainStack.distribution = .fill
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let leftPanel = makeLeftPanel()
        let rightPanel = makeRightPanel()
        leftPanel.widthAnchor.constraint(equalToConstant: 360).isActive = true

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true

        mainStack.addArrangedSubview(leftPanel)
        mainStack.addArrangedSubview(divider)
        mainStack.addArrangedSubview(rightPanel)
    }

    private func makeLeftPanel() -> NSView {
        let panel = NSView()
        panel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panel.topAnchor),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
        ])

        let title = NSTextField(labelWithString: "Guide Sync Targets")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.textColor = .labelColor
        stack.addArrangedSubview(title)

        stack.addArrangedSubview(makeCallout(
            text: "Manage explicit project roots. Sync writes the managed AGENTS.md and CLAUDE.md templates stored under ~/.config/spectra/guides/."
        ))

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.distribution = .fillEqually
        buttonRow.addArrangedSubview(addTargetButton)
        buttonRow.addArrangedSubview(addCurrentProjectButton)
        stack.addArrangedSubview(buttonRow)

        targetsStack.orientation = .vertical
        targetsStack.alignment = .leading
        targetsStack.distribution = .fill
        targetsStack.spacing = 10
        targetsStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        targetsStack.translatesAutoresizingMaskIntoConstraints = true

        targetsDocumentView.addSubview(targetsStack)
        targetsDocumentView.translatesAutoresizingMaskIntoConstraints = true

        targetsScrollView.documentView = targetsDocumentView
        targetsScrollView.hasVerticalScroller = true
        targetsScrollView.hasHorizontalScroller = false
        targetsScrollView.autohidesScrollers = true
        targetsScrollView.drawsBackground = true
        targetsScrollView.backgroundColor = Self.listSurfaceColor
        targetsScrollView.borderType = .bezelBorder
        targetsScrollView.translatesAutoresizingMaskIntoConstraints = false
        targetsScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        stack.addArrangedSubview(targetsScrollView)

        let syncRow = NSStackView()
        syncRow.orientation = .vertical
        syncRow.spacing = 10
        syncRow.addArrangedSubview(syncCurrentProjectButton)
        syncRow.addArrangedSubview(syncAllEnabledButton)
        stack.addArrangedSubview(syncRow)

        return panel
    }

    private func makeRightPanel() -> NSView {
        let panel = NSView()
        panel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panel.topAnchor),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
        ])

        previewTitleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        previewTitleLabel.textColor = .labelColor
        stack.addArrangedSubview(previewTitleLabel)

        stack.addArrangedSubview(makeCallout(
            text: "Raw mode is editable and can be saved back to ~/.config/spectra/guides/. Preview mode is read-only."
        ))

        configureTextView(previewTextView, fontSize: 13)
        previewScrollView.documentView = previewTextView
        previewScrollView.hasVerticalScroller = true
        previewScrollView.hasHorizontalScroller = false
        previewScrollView.autohidesScrollers = true
        previewScrollView.drawsBackground = true
        previewScrollView.backgroundColor = Self.editorSurfaceColor
        previewScrollView.borderType = .bezelBorder
        previewScrollView.translatesAutoresizingMaskIntoConstraints = false

        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(previewScrollView)
        NSLayoutConstraint.activate([
            previewScrollView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewScrollView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            previewScrollView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewScrollView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
        ])
        stack.addArrangedSubview(previewContainer)

        let resultTitle = NSTextField(labelWithString: "Last Sync Result")
        resultTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        resultTitle.textColor = .labelColor
        stack.addArrangedSubview(resultTitle)

        configureTextView(resultTextView, fontSize: 12)
        let resultScrollView = NSScrollView()
        resultScrollView.documentView = resultTextView
        resultScrollView.hasVerticalScroller = true
        resultScrollView.hasHorizontalScroller = false
        resultScrollView.autohidesScrollers = true
        resultScrollView.drawsBackground = true
        resultScrollView.backgroundColor = Self.editorSurfaceColor
        resultScrollView.borderType = .bezelBorder
        resultScrollView.translatesAutoresizingMaskIntoConstraints = false
        resultScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        stack.addArrangedSubview(resultScrollView)

        return panel
    }

    private func configureTextView(_ textView: NSTextView, fontSize: CGFloat) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.delegate = self
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    }

    private func makeCallout(text: String) -> NSView {
        let container = DynamicSurfaceView()
        container.cornerRadius = 10
        container.backgroundColorProvider = { Self.calloutBackgroundColor }
        container.borderColorProvider = { Self.calloutBorderColor }

        let label = NSTextField(wrappingLabelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = Self.calloutTextColor
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        return container
    }

    // MARK: - Preview

    private func refreshPreview() {
        if let index = service.templateKinds.firstIndex(of: selectedGuide) {
            guideSelector.selectedSegment = index
        }
        previewTitleLabel.stringValue = "Preview — \(selectedGuide.fileName)"
        do {
            let content = try service.loadGuideTemplate(selectedGuide)
            savedTemplateMarkdown = content
            previewMarkdown = content
        } catch {
            let errorText = "Unable to load managed template: \(error.localizedDescription)"
            savedTemplateMarkdown = errorText
            previewMarkdown = errorText
        }
        previewTextView.string = previewMarkdown
        previewTextView.scrollToBeginningOfDocument(nil)
        applyPreviewMode()
    }

    private func applyPreviewMode() {
        if isRenderedMode {
            showRenderedPreview()
        } else {
            showRawPreview()
        }
    }

    private func showRawPreview() {
        previewWebView?.isHidden = true
        previewScrollView.isHidden = false
        previewTextView.isEditable = true
        previewTextView.string = previewMarkdown
        previewTextView.scrollToBeginningOfDocument(nil)
    }

    private func showRenderedPreview() {
        let webView = ensurePreviewWebView()
        previewTextView.isEditable = false
        previewScrollView.isHidden = true
        webView.isHidden = false
        webView.loadHTMLString(MarkdownPreviewSupport.html(for: previewMarkdown), baseURL: nil)
    }

    private func ensurePreviewWebView() -> WKWebView {
        if let webView = previewWebView { return webView }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground")
        previewContainer.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            webView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
        ])
        previewWebView = webView
        return webView
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        if navigationAction.navigationType == .other {
            decisionHandler(.allow, preferences)
        } else {
            if let url = navigationAction.request.url,
               url.scheme == "https" || url.scheme == "http" {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel, preferences)
        }
    }

    // MARK: - Data

    private func loadTargets() {
        targets = store.loadTargets()
    }

    private func persistTargets() {
        do {
            try store.saveTargets(targets)
        } catch {
            showStatus("Failed to save targets: \(error.localizedDescription)", isError: true)
        }
    }

    private func renderTargets() {
        targetsStack.arrangedSubviews.forEach { view in
            targetsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard !targets.isEmpty else {
            let emptyState = NSTextField(wrappingLabelWithString: "No targets yet. Add a project root or use Add Current Project.")
            emptyState.font = .systemFont(ofSize: 12.5)
            emptyState.textColor = .secondaryLabelColor
            emptyState.maximumNumberOfLines = 0
            emptyState.lineBreakMode = .byWordWrapping
            targetsStack.addArrangedSubview(emptyState)
            needsLayout = true
            return
        }

        for target in targets {
            targetsStack.addArrangedSubview(makeTargetRow(for: target))
        }
        needsLayout = true
    }

    private func makeTargetRow(for target: GuideSyncTarget) -> NSView {
        let exists = FileManager.default.fileExists(atPath: target.path)

        let surface = DynamicSurfaceView()
        surface.cornerRadius = 10
        surface.backgroundColorProvider = {
            Self.targetCardBackgroundColor(enabled: target.isEnabled, exists: exists)
        }
        surface.borderColorProvider = {
            Self.targetCardBorderColor(enabled: target.isEnabled, exists: exists)
        }
        surface.translatesAutoresizingMaskIntoConstraints = false

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 6
        container.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        container.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: surface.topAnchor),
            container.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
        ])

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 8
        topRow.alignment = .centerY

        let toggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleTargetEnabled(_:)))
        toggle.identifier = NSUserInterfaceItemIdentifier(target.id.uuidString)
        toggle.state = target.isEnabled ? .on : .off
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        topRow.addArrangedSubview(toggle)

        let nameLabel = NSTextField(labelWithString: target.displayName)
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = Self.targetPrimaryTextColor(enabled: target.isEnabled, exists: exists)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        topRow.addArrangedSubview(nameLabel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        topRow.addArrangedSubview(spacer)

        let status = NSTextField(labelWithString: exists ? "Ready" : "Missing")
        status.font = .systemFont(ofSize: 11.5, weight: .semibold)
        status.textColor = exists ? Self.readyTextColor : .systemRed
        topRow.addArrangedSubview(status)

        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeTarget(_:)))
        removeButton.identifier = NSUserInterfaceItemIdentifier(target.id.uuidString)
        removeButton.controlSize = .small
        removeButton.bezelStyle = .rounded
        topRow.addArrangedSubview(removeButton)

        let pathLabel = NSTextField(labelWithString: target.path)
        pathLabel.font = .systemFont(ofSize: 11.5)
        pathLabel.textColor = exists
            ? Self.targetSecondaryTextColor(enabled: target.isEnabled)
            : .systemRed
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.toolTip = target.path

        container.addArrangedSubview(topRow)
        container.addArrangedSubview(pathLabel)
        return surface
    }

    private func layoutTargetsDocumentView() {
        let width = max(0, targetsScrollView.contentView.bounds.width)
        let stackHeight = targetsStack.fittingSize.height
        let documentHeight = max(stackHeight + 16, targetsScrollView.contentView.bounds.height)

        targetsDocumentView.frame = NSRect(x: 0, y: 0, width: width, height: documentHeight)
        targetsStack.frame = NSRect(x: 0, y: 0, width: width, height: stackHeight)
    }

    private func updateActionButtonStates() {
        let hasEnabledTargets = targets.contains(where: \.isEnabled)
        let hasCurrentProject = currentProjectPathProvider() != nil
        addTargetButton.isEnabled = !isSyncing
        addCurrentProjectButton.isEnabled = !isSyncing && hasCurrentProject
        syncCurrentProjectButton.isEnabled = !isSyncing && hasCurrentProject
        syncAllEnabledButton.isEnabled = !isSyncing && hasEnabledTargets
        saveButton.isEnabled = !isSyncing && hasUnsavedChanges
    }

    private func showStatus(_ text: String, isError: Bool) {
        let color = isError ? NSColor.systemRed : NSColor.labelColor
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: color,
        ])
        resultTextView.textStorage?.setAttributedString(attributed)
        resultTextView.scrollToBeginningOfDocument(nil)
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === previewTextView else { return }
        previewMarkdown = previewTextView.string
        updateActionButtonStates()
        if isRenderedMode {
            applyPreviewMode()
        }
    }

    private func promptToHandleUnsavedChanges(reason: String, then proceed: @escaping () -> Void) {
        guard hasUnsavedChanges else {
            proceed()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Unsaved template changes"
        alert.informativeText = "Save changes to \(selectedGuide.fileName) before \(reason)?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.saveCurrentTemplate(nil)
                if !self.hasUnsavedChanges { proceed() }
            case .alertSecondButtonReturn:
                self.previewMarkdown = self.savedTemplateMarkdown
                self.previewTextView.string = self.savedTemplateMarkdown
                self.updateActionButtonStates()
                proceed()
            default:
                return
            }
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func upsertTarget(path: String) {
        let normalizedPath = GuideSyncTarget.normalizedPath(path)
        guard !normalizedPath.isEmpty else { return }

        if let index = targets.firstIndex(where: { GuideSyncTarget.normalizedPath($0.path) == normalizedPath }) {
            if !targets[index].isEnabled {
                targets[index].isEnabled = true
                persistTargets()
                showStatus("Re-enabled target: \(normalizedPath)", isError: false)
            } else {
                showStatus("Target already exists: \(normalizedPath)", isError: false)
            }
            return
        }

        targets.append(GuideSyncTarget(
            path: normalizedPath,
            alias: URL(fileURLWithPath: normalizedPath).lastPathComponent
        ))
        persistTargets()
        showStatus("Added target: \(normalizedPath)", isError: false)
    }

    private func confirmSync(targetCount: Int, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Sync managed templates?"
        alert.informativeText = "This will write AGENTS.md and CLAUDE.md into \(targetCount) selected project root(s). Existing files with different content will be overwritten."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Sync")
        alert.addButton(withTitle: "Cancel")

        if let window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn { action() }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            action()
        }
    }

    private func performSync(on targetsToSync: [GuideSyncTarget]) {
        isSyncing = true
        showStatus("Syncing \(targetsToSync.count) target(s)…", isError: false)

        DispatchQueue.global(qos: .userInitiated).async { [service] in
            let results = service.syncGuides(toTargets: targetsToSync)
            let summary = service.summaryText(for: results)
            let hasFailures = results.contains { !$0.isSuccess }

            DispatchQueue.main.async { [weak self] in
                self?.isSyncing = false
                self?.showStatus(summary, isError: hasFailures)
                self?.renderTargets()
            }
        }
    }

    private func targetID(from sender: NSControl) -> UUID? {
        guard let raw = sender.identifier?.rawValue else { return nil }
        return UUID(uuidString: raw)
    }

    // MARK: - Actions

    @objc private func saveCurrentTemplate(_ sender: Any?) {
        do {
            try service.saveGuideTemplate(selectedGuide, content: previewMarkdown)
            savedTemplateMarkdown = previewMarkdown
            updateActionButtonStates()
            showStatus("Saved \(selectedGuide.fileName) to \(service.templateFileURL(for: selectedGuide).path)", isError: false)
        } catch {
            showStatus("Failed to save \(selectedGuide.fileName): \(error.localizedDescription)", isError: true)
        }
    }

    @objc private func guideSelectionChanged(_ sender: NSSegmentedControl) {
        guard sender.selectedSegment >= 0,
              sender.selectedSegment < service.templateKinds.count else { return }
        let nextGuide = service.templateKinds[sender.selectedSegment]
        let currentIndex = service.templateKinds.firstIndex(of: selectedGuide) ?? 0
        guard nextGuide != selectedGuide else { return }

        sender.selectedSegment = currentIndex
        promptToHandleUnsavedChanges(reason: "switching guides") { [weak self] in
            self?.selectedGuide = nextGuide
            self?.refreshPreview()
        }
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        isRenderedMode = sender.selectedSegment == 1
    }

    @objc private func addTarget(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a project root to receive the managed templates"

        let handleURL: (URL?) -> Void = { [weak self] url in
            guard let url else { return }
            self?.upsertTarget(path: url.path)
        }

        if let window {
            panel.beginSheetModal(for: window) { response in
                if response == .OK { handleURL(panel.url) }
            }
        } else if panel.runModal() == .OK {
            handleURL(panel.url)
        }
    }

    @objc private func addCurrentProject(_ sender: Any?) {
        guard let path = currentProjectPathProvider() else {
            showStatus("No current sidebar project is available.", isError: true)
            return
        }
        upsertTarget(path: path)
    }

    @objc private func toggleTargetEnabled(_ sender: NSButton) {
        guard let id = targetID(from: sender),
              let index = targets.firstIndex(where: { $0.id == id }) else { return }
        targets[index].isEnabled = sender.state == .on
        persistTargets()
    }

    @objc private func removeTarget(_ sender: NSButton) {
        guard let id = targetID(from: sender) else { return }
        targets.removeAll { $0.id == id }
        persistTargets()
        showStatus("Removed target.", isError: false)
    }

    @objc private func syncCurrentProject(_ sender: Any?) {
        guard let path = currentProjectPathProvider() else {
            showStatus("No current sidebar project is available.", isError: true)
            return
        }

        let target = GuideSyncTarget(path: path, alias: URL(fileURLWithPath: path).lastPathComponent)
        promptToHandleUnsavedChanges(reason: "syncing") { [weak self] in
            self?.confirmSync(targetCount: 1) { [weak self] in
                self?.performSync(on: [target])
            }
        }
    }

    @objc private func syncAllEnabled(_ sender: Any?) {
        let enabledTargets = targets.filter(\.isEnabled)
        guard !enabledTargets.isEmpty else {
            showStatus("No enabled targets available.", isError: true)
            return
        }

        promptToHandleUnsavedChanges(reason: "syncing") { [weak self] in
            self?.confirmSync(targetCount: enabledTargets.count) { [weak self] in
                self?.performSync(on: enabledTargets)
            }
        }
    }
}

// MARK: - Dynamic Colors

private extension GuideSyncContentView {
    static var listSurfaceColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.16, alpha: 1)
                : NSColor(calibratedRed: 0.965, green: 0.968, blue: 0.975, alpha: 1)
        }
    }

    static var editorSurfaceColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.14, alpha: 1)
                : NSColor(calibratedRed: 0.985, green: 0.986, blue: 0.99, alpha: 1)
        }
    }

    static var calloutBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.17, green: 0.18, blue: 0.21, alpha: 1)
                : NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.985, alpha: 1)
        }
    }

    static var calloutBorderColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 1, alpha: 0.08)
                : NSColor(calibratedRed: 0.84, green: 0.87, blue: 0.93, alpha: 1)
        }
    }

    static var calloutTextColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.8, green: 0.82, blue: 0.86, alpha: 1)
                : NSColor(calibratedRed: 0.35, green: 0.39, blue: 0.48, alpha: 1)
        }
    }

    static var readyTextColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.systemGreen
                : NSColor(calibratedRed: 0.14, green: 0.55, blue: 0.29, alpha: 1)
        }
    }

    static func targetCardBackgroundColor(enabled: Bool, exists: Bool) -> NSColor {
        if !exists {
            return NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(calibratedRed: 0.28, green: 0.17, blue: 0.18, alpha: 1)
                    : NSColor(calibratedRed: 0.995, green: 0.945, blue: 0.945, alpha: 1)
            }
        }

        if enabled {
            return NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.22, alpha: 1)
                    : NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1)
            }
        }

        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.18, alpha: 1)
                : NSColor(calibratedRed: 0.94, green: 0.945, blue: 0.955, alpha: 1)
        }
    }

    static func targetCardBorderColor(enabled: Bool, exists: Bool) -> NSColor {
        if !exists { return NSColor.systemRed.withAlphaComponent(0.35) }

        return NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return enabled
                    ? NSColor(calibratedWhite: 1, alpha: 0.1)
                    : NSColor(calibratedWhite: 1, alpha: 0.06)
            }
            return enabled
                ? NSColor(calibratedRed: 0.84, green: 0.87, blue: 0.93, alpha: 1)
                : NSColor(calibratedRed: 0.86, green: 0.88, blue: 0.92, alpha: 1)
        }
    }

    static func targetPrimaryTextColor(enabled: Bool, exists: Bool) -> NSColor {
        if !exists { return .labelColor }
        return enabled ? .labelColor : .secondaryLabelColor
    }

    static func targetSecondaryTextColor(enabled: Bool) -> NSColor {
        enabled ? .secondaryLabelColor : .tertiaryLabelColor
    }
}

// MARK: - Helper Views

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class DynamicSurfaceView: NSView {
    var backgroundColorProvider: () -> NSColor = { .clear }
    var borderColorProvider: () -> NSColor = { .clear }
    var cornerRadius: CGFloat = 10
    var borderWidth: CGFloat = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = borderWidth
        layer?.backgroundColor = backgroundColorProvider().cgColor
        layer?.borderColor = borderColorProvider().cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
