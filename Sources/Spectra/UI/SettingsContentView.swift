import AppKit
import UniformTypeIdentifiers

/// Settings form content designed to be embedded inside an OverlayPanel.
/// Replaces SettingsWindowController with an in-window overlay approach.
class SettingsContentView: NSView {
    private let configManager: ConfigManager
    private var currentTab: Tab = .general
    private let segmentedControl: NSSegmentedControl
    private let formContainer = NSView()

    private var themeObserver: NSObjectProtocol?
    private var cachedTabViews: [Tab: NSView] = [:]
    private var activeTabView: NSView?
    private var tabsNeedingRefresh = Set<Tab>()
    private var isProgrammaticUIThemeSelection = false
    private var uiThemeSelectionDirty = false

    // General tab
    private var windowWidthField: NSTextField!
    private var windowHeightField: NSTextField!

    // Appearance tab
    private var appearancePopup: NSPopUpButton!
    private var uiThemePopup: NSPopUpButton!
    private var terminalThemePopup: NSPopUpButton!
    private var opacitySlider: NSSlider!
    private var opacityLabel: NSTextField!
    private var blurPopup: NSPopUpButton!
    private var cursorPopup: NSPopUpButton!
    private var cursorBlinkCheck: NSButton!
    private var paddingXField: NSTextField!
    private var paddingYField: NSTextField!
    private var paddingBalancePopup: NSPopUpButton!

    // Font tab
    private static var cachedMonospaceFonts: [String]?
    private var fontFamilyPopup: NSPopUpButton!
    private var fontSizeField: NSTextField!
    private var fontSizeStepper: NSStepper!
    private var fontPreview: NSTextField!

    enum Tab: Int, CaseIterable {
        case general = 0
        case appearance = 1
        case font = 2

        var label: String {
            switch self {
            case .general: return "General"
            case .appearance: return "Appearance"
            case .font: return "Font"
            }
        }
    }

    init(configManager: ConfigManager) {
        self.configManager = configManager
        segmentedControl = NSSegmentedControl(
            labels: Tab.allCases.map(\.label),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        super.init(frame: .zero)

        segmentedControl.target = self
        segmentedControl.action = #selector(tabChanged(_:))
        segmentedControl.selectedSegment = 0

        setupLayout()
        setupObservers()
        showTab(.general)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
    }

    /// The segmented control to be placed in the overlay header.
    var headerToolbar: NSView { segmentedControl }

    // MARK: - Layout

    private func setupLayout() {
        formContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(formContainer)
        NSLayoutConstraint.activate([
            formContainer.topAnchor.constraint(equalTo: topAnchor),
            formContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            formContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            formContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupObservers() {
        themeObserver = NotificationCenter.default.addObserver(
            forName: .spectraThemeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleThemeDidChange()
        }
    }

    // MARK: - Tab Switching

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        guard let tab = Tab(rawValue: sender.selectedSegment) else { return }
        showTab(tab)
    }

    private func showTab(_ tab: Tab) {
        currentTab = tab
        segmentedControl.selectedSegment = tab.rawValue

        activeTabView?.removeFromSuperview()

        let tabView = view(for: tab)
        activeTabView = tabView
        attachTabView(tabView)
        refreshTabIfNeeded(tab)
    }

    private func view(for tab: Tab) -> NSView {
        if let cached = cachedTabViews[tab] {
            return cached
        }

        let tabView: NSView
        switch tab {
        case .general:
            tabView = buildGeneralTab()
        case .appearance:
            tabView = buildAppearanceTab()
        case .font:
            tabView = buildFontTab()
        }

        cachedTabViews[tab] = tabView
        tabsNeedingRefresh.remove(tab)
        return tabView
    }

    private func attachTabView(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        formContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: formContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: formContainer.bottomAnchor),
        ])
    }

    private func refreshTabIfNeeded(_ tab: Tab) {
        guard tabsNeedingRefresh.contains(tab) else { return }
        refreshTab(tab)
        tabsNeedingRefresh.remove(tab)
    }

    private func refreshTab(_ tab: Tab) {
        switch tab {
        case .general:
            refreshGeneralControlsFromConfig()
        case .appearance:
            refreshAppearanceControlsFromConfig()
        case .font:
            refreshFontControlsFromConfig()
        }
    }

    private func refreshCurrentTabFromModel() {
        guard cachedTabViews[currentTab] != nil else { return }
        refreshTab(currentTab)
        tabsNeedingRefresh.remove(currentTab)
    }

    private func invalidateTabsAfterExternalConfigReload() {
        uiThemeSelectionDirty = false
        tabsNeedingRefresh.formUnion(Tab.allCases)
        refreshCurrentTabFromModel()
    }

    private func handleThemeDidChange() {
        guard cachedTabViews[.appearance] != nil else { return }
        if currentTab == .appearance {
            syncAppearanceThemeControlsFromModel()
        } else {
            tabsNeedingRefresh.insert(.appearance)
        }
    }

    // MARK: - Config Helpers

    private func cfg(_ key: String, default d: String = "") -> String {
        SpectraConfig.read(key, default: d)
    }

    private func titleForAppearanceMode(_ mode: String) -> String {
        switch mode {
        case "light": return "Light"
        case "dark": return "Dark"
        default: return "Auto"
        }
    }

    // MARK: - General Tab

    private func buildGeneralTab() -> NSView {
        let stack = makeStack()

        windowWidthField = addField(to: stack, label: "Window Width (cols):", value: cfg("window-width", default: "120"))
        windowHeightField = addField(to: stack, label: "Window Height (rows):", value: cfg("window-height", default: "36"))

        stack.addArrangedSubview(NSView())

        let importRow = NSStackView()
        importRow.orientation = .horizontal; importRow.spacing = 8
        let importGhosttyBtn = NSButton(title: "Import Ghostty Config", target: self,
                                         action: #selector(importFromGhostty(_:)))
        importGhosttyBtn.bezelStyle = .rounded
        let importFileBtn = NSButton(title: "Import File…", target: self,
                                      action: #selector(importFromFile(_:)))
        importFileBtn.bezelStyle = .rounded
        importRow.addArrangedSubview(importGhosttyBtn)
        importRow.addArrangedSubview(importFileBtn)
        stack.addArrangedSubview(importRow)

        addApplyButton(to: stack)
        return embedScrollableStack(stack)
    }

    private func refreshGeneralControlsFromConfig() {
        windowWidthField?.stringValue = cfg("window-width", default: "120")
        windowHeightField?.stringValue = cfg("window-height", default: "36")
    }

    // MARK: - Appearance Tab

    private func buildAppearanceTab() -> NSView {
        let stack = makeStack()

        addSectionHeader(to: stack, title: "UI THEME")

        appearancePopup = addPopupRow(to: stack, label: "Base Appearance:",
                                       items: ["Auto", "Light", "Dark"],
                                       selected: titleForAppearanceMode(SpectraThemeManager.shared.configuredAppearanceMode()))

        uiThemePopup = NSPopUpButton()
        uiThemePopup.target = self
        uiThemePopup.action = #selector(uiThemePopupSelectionChanged(_:))
        rebuildUIThemePopup()
        let themeRow = NSStackView()
        themeRow.orientation = .horizontal; themeRow.spacing = 8
        let tLbl = NSTextField(labelWithString: "UI Theme:")
        tLbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        tLbl.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        themeRow.addArrangedSubview(tLbl)
        themeRow.addArrangedSubview(uiThemePopup)
        stack.addArrangedSubview(themeRow)

        let themeActionRow = NSStackView()
        themeActionRow.orientation = .horizontal; themeActionRow.spacing = 8
        let importThemeBtn = NSButton(title: "Import…", target: self,
                                      action: #selector(importUIThemeFile(_:)))
        importThemeBtn.bezelStyle = .rounded
        let previewThemeBtn = NSButton(title: "Preview", target: self,
                                        action: #selector(previewSelectedUITheme(_:)))
        previewThemeBtn.bezelStyle = .rounded
        let applyThemeBtn = NSButton(title: "Apply", target: self,
                                      action: #selector(applySelectedUITheme(_:)))
        applyThemeBtn.bezelStyle = .rounded
        let resetThemeBtn = NSButton(title: "Use System Default", target: self,
                                     action: #selector(resetUIThemeSelection(_:)))
        resetThemeBtn.bezelStyle = .rounded
        themeActionRow.addArrangedSubview(importThemeBtn)
        themeActionRow.addArrangedSubview(previewThemeBtn)
        themeActionRow.addArrangedSubview(applyThemeBtn)
        themeActionRow.addArrangedSubview(resetThemeBtn)
        stack.addArrangedSubview(themeActionRow)

        addSectionHeader(to: stack, title: "TERMINAL THEME")
        terminalThemePopup = NSPopUpButton()
        let terminalThemeRow = NSStackView()
        terminalThemeRow.orientation = .horizontal; terminalThemeRow.spacing = 8
        let terminalThemeLabel = NSTextField(labelWithString: "Ghostty Theme:")
        terminalThemeLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        terminalThemeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        terminalThemeRow.addArrangedSubview(terminalThemeLabel)
        terminalThemeRow.addArrangedSubview(terminalThemePopup)
        stack.addArrangedSubview(terminalThemeRow)
        rebuildTerminalThemePopup()
        addNote(to: stack, text: "Uses bundled Ghostty themes only in this implementation slice")

        addSectionHeader(to: stack, title: "BACKGROUND")

        let opacity = Double(cfg("background-opacity", default: "1")) ?? 1.0
        let opacityRow = NSStackView()
        opacityRow.orientation = .horizontal; opacityRow.spacing = 8
        let oLbl = NSTextField(labelWithString: "Opacity:")
        oLbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        oLbl.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        opacitySlider = NSSlider(value: opacity, minValue: 0.0, maxValue: 1.0,
                                 target: self, action: #selector(opacityChanged(_:)))
        opacityLabel = NSTextField(labelWithString: String(format: "%.0f%%", opacity * 100))
        opacityLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        opacityRow.addArrangedSubview(oLbl)
        opacityRow.addArrangedSubview(opacitySlider)
        opacityRow.addArrangedSubview(opacityLabel)
        stack.addArrangedSubview(opacityRow)

        let blurValue = cfg("background-blur", default: "false")
        let blurSelected = blurValue == "false" ? "Off" : "On"
        blurPopup = addPopupRow(to: stack, label: "Blur:",
                                 items: ["Off", "On"],
                                 selected: blurSelected)
        addNote(to: stack, text: "Only visible when opacity is below 100%")

        addSectionHeader(to: stack, title: "CURSOR")

        let cursorRow = NSStackView()
        cursorRow.orientation = .horizontal; cursorRow.spacing = 8
        let cLbl = NSTextField(labelWithString: "Cursor Style:")
        cLbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        cLbl.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        cursorPopup = NSPopUpButton()
        cursorPopup.addItems(withTitles: ["block", "bar", "underline"])
        cursorPopup.selectItem(withTitle: cfg("cursor-style", default: "block"))
        cursorBlinkCheck = NSButton(checkboxWithTitle: "Blink", target: nil, action: nil)
        cursorBlinkCheck.state = cfg("cursor-style-blink", default: "true") == "true" ? .on : .off
        cursorRow.addArrangedSubview(cLbl)
        cursorRow.addArrangedSubview(cursorPopup)
        cursorRow.addArrangedSubview(cursorBlinkCheck)
        stack.addArrangedSubview(cursorRow)

        addSectionHeader(to: stack, title: "PADDING")

        paddingXField = addField(to: stack, label: "Padding X:", value: cfg("window-padding-x", default: "2"))
        paddingYField = addField(to: stack, label: "Padding Y:", value: cfg("window-padding-y", default: "2"))
        addNote(to: stack, text: "Takes effect on new terminals (new tab or split)")

        paddingBalancePopup = NSPopUpButton()
        let paddingBalanceRow = NSStackView()
        paddingBalanceRow.orientation = .horizontal; paddingBalanceRow.spacing = 8
        let paddingBalanceLabel = NSTextField(labelWithString: "Balance:")
        paddingBalanceLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        paddingBalanceLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        paddingBalanceRow.addArrangedSubview(paddingBalanceLabel)
        paddingBalanceRow.addArrangedSubview(paddingBalancePopup)
        stack.addArrangedSubview(paddingBalanceRow)
        refreshPaddingBalancePopupSelection()

        addApplyButton(to: stack)
        return embedScrollableStack(stack)
    }

    private func syncAppearanceThemeControlsFromModel(reloadThemeOptions: Bool = false) {
        guard appearancePopup != nil else { return }

        appearancePopup.selectItem(withTitle: titleForAppearanceMode(SpectraThemeManager.shared.configuredAppearanceMode()))

        if reloadThemeOptions {
            rebuildUIThemePopup()
        } else {
            syncUIThemePopupSelectionFromModel()
        }
    }

    private func refreshAppearanceControlsFromConfig(reloadThemeOptions: Bool = false) {
        guard appearancePopup != nil else { return }

        syncAppearanceThemeControlsFromModel(reloadThemeOptions: reloadThemeOptions)

        rebuildTerminalThemePopup()

        let opacity = Double(cfg("background-opacity", default: "1")) ?? 1.0
        opacitySlider?.doubleValue = opacity
        if let opacitySlider {
            opacityChanged(opacitySlider)
        }

        blurPopup?.selectItem(withTitle: cfg("background-blur", default: "false") == "false" ? "Off" : "On")
        cursorPopup?.selectItem(withTitle: cfg("cursor-style", default: "block"))
        cursorBlinkCheck?.state = cfg("cursor-style-blink", default: "true") == "true" ? .on : .off
        paddingXField?.stringValue = cfg("window-padding-x", default: "2")
        paddingYField?.stringValue = cfg("window-padding-y", default: "2")
        refreshPaddingBalancePopupSelection()
    }

    private func rebuildTerminalThemePopup() {
        guard let terminalThemePopup else { return }
        let configuredGhosttyTheme = cfg("theme")
        var ghosttyThemes = ["Follow Appearance"] + GhosttyThemeCatalog.bundledThemeNames()
        if !configuredGhosttyTheme.isEmpty && !ghosttyThemes.contains(configuredGhosttyTheme) {
            ghosttyThemes.insert(configuredGhosttyTheme, at: 1)
        }
        terminalThemePopup.removeAllItems()
        terminalThemePopup.addItems(withTitles: ghosttyThemes)
        terminalThemePopup.selectItem(withTitle: configuredGhosttyTheme.isEmpty ? "Follow Appearance" : configuredGhosttyTheme)
    }

    private func refreshPaddingBalancePopupSelection() {
        guard let paddingBalancePopup else { return }
        let balanceValue = cfg("window-padding-balance", default: "false")
        let balanceSelected: String = {
            switch balanceValue {
            case "true": return "On"
            case "equal": return "Equal"
            default: return "Off"
            }
        }()
        if paddingBalancePopup.numberOfItems == 0 {
            paddingBalancePopup.addItems(withTitles: ["Off", "On", "Equal"])
        }
        paddingBalancePopup.selectItem(withTitle: balanceSelected)
    }

    // MARK: - Font Tab

    private func buildFontTab() -> NSView {
        let stack = makeStack()

        let familyRow = NSStackView()
        familyRow.orientation = .horizontal; familyRow.spacing = 8
        let fLbl = NSTextField(labelWithString: "Font Family:")
        fLbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        fLbl.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        fontFamilyPopup = NSPopUpButton()
        fontFamilyPopup.target = self
        fontFamilyPopup.action = #selector(fontFamilyChanged(_:))

        let monoFonts = installedMonospaceFonts()
        fontFamilyPopup.addItems(withTitles: monoFonts)

        let currentFamily = cfg("font-family")
        if !currentFamily.isEmpty, let match = monoFonts.first(where: {
            $0.caseInsensitiveCompare(currentFamily) == .orderedSame
        }) {
            fontFamilyPopup.selectItem(withTitle: match)
        }
        familyRow.addArrangedSubview(fLbl)
        familyRow.addArrangedSubview(fontFamilyPopup)
        stack.addArrangedSubview(familyRow)

        let sizeRow = NSStackView()
        sizeRow.orientation = .horizontal; sizeRow.spacing = 8
        let sLbl = NSTextField(labelWithString: "Font Size:")
        sLbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        sLbl.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        let size = Int(Double(cfg("font-size", default: "13")) ?? 13)
        fontSizeField = NSTextField(string: "\(size)")
        fontSizeField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        fontSizeStepper = NSStepper()
        fontSizeStepper.minValue = 6; fontSizeStepper.maxValue = 72
        fontSizeStepper.integerValue = size
        fontSizeStepper.target = self; fontSizeStepper.action = #selector(sizeStepperChanged(_:))
        sizeRow.addArrangedSubview(sLbl)
        sizeRow.addArrangedSubview(fontSizeField)
        sizeRow.addArrangedSubview(fontSizeStepper)
        stack.addArrangedSubview(sizeRow)

        fontPreview = NSTextField(labelWithString: "AaBbCcDdEeFf 0123456789 ~!@#$%")
        fontPreview.alignment = .center
        updateFontPreview()
        stack.addArrangedSubview(fontPreview)

        addApplyButton(to: stack)
        return embedScrollableStack(stack)
    }

    private func refreshFontControlsFromConfig() {
        guard fontFamilyPopup != nil else { return }
        let currentFamily = cfg("font-family")
        if !currentFamily.isEmpty {
            if let match = installedMonospaceFonts().first(where: {
                $0.caseInsensitiveCompare(currentFamily) == .orderedSame
            }) {
                fontFamilyPopup.selectItem(withTitle: match)
            }
        }

        let size = Int(Double(cfg("font-size", default: "13")) ?? 13)
        fontSizeField?.stringValue = "\(size)"
        fontSizeStepper?.integerValue = size
        updateFontPreview()
    }

    private func installedMonospaceFonts() -> [String] {
        if let cached = Self.cachedMonospaceFonts { return cached }
        let fm = NSFontManager.shared
        let result = fm.availableFontFamilies.filter { family in
            guard let members = fm.availableMembers(ofFontFamily: family),
                  let first = members.first,
                  let fontName = first[0] as? String,
                  let font = NSFont(name: fontName, size: 13) else { return false }
            return font.isFixedPitch
                || family.localizedCaseInsensitiveContains("mono")
                || family.localizedCaseInsensitiveContains("code")
                || family.localizedCaseInsensitiveContains("console")
                || family.localizedCaseInsensitiveContains("terminal")
        }.sorted()
        Self.cachedMonospaceFonts = result
        return result
    }

    private func updateFontPreview() {
        guard let preview = fontPreview else { return }
        let family = fontFamilyPopup?.titleOfSelectedItem ?? ""
        let size = CGFloat(fontSizeStepper?.integerValue ?? 13)
        let font: NSFont = {
            if family.isEmpty {
                return .monospacedSystemFont(ofSize: size, weight: .regular)
            }
            return NSFont(name: family, size: size)
                ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        }()
        preview.font = font
    }

    // MARK: - Actions

    @objc private func opacityChanged(_ sender: NSSlider) {
        opacityLabel.stringValue = String(format: "%.0f%%", sender.doubleValue * 100)
    }

    @objc private func sizeStepperChanged(_ sender: NSStepper) {
        fontSizeField.stringValue = "\(sender.integerValue)"
        updateFontPreview()
    }

    @objc private func fontFamilyChanged(_ sender: NSPopUpButton) {
        updateFontPreview()
    }

    @objc private func uiThemePopupSelectionChanged(_ sender: NSPopUpButton) {
        guard !isProgrammaticUIThemeSelection else { return }
        uiThemeSelectionDirty = true
    }

    private func themeSelectionIdentifier(for theme: SpectraUITheme) -> String {
        "\(theme.source.rawValue)::\(theme.id)"
    }

    private func selectedUIThemeIdentifier() -> String? {
        uiThemePopup?.selectedItem?.representedObject as? String
    }

    private func setUIThemePopupSelection(identifier: String) {
        guard let uiThemePopup else { return }
        guard let idx = uiThemePopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == identifier }) else {
            return
        }
        isProgrammaticUIThemeSelection = true
        uiThemePopup.selectItem(at: idx)
        isProgrammaticUIThemeSelection = false
    }

    private func syncUIThemePopupSelectionFromModel() {
        guard !uiThemeSelectionDirty else { return }
        let effectiveTheme = SpectraThemeManager.shared.effectiveTheme
        setUIThemePopupSelection(identifier: themeSelectionIdentifier(for: effectiveTheme))
    }

    private func rebuildUIThemePopup() {
        guard let uiThemePopup else { return }
        let manualSelection = uiThemeSelectionDirty ? selectedUIThemeIdentifier() : nil
        let allThemes = SpectraThemeManager.shared.allUIThemes()

        isProgrammaticUIThemeSelection = true
        uiThemePopup.removeAllItems()
        for theme in allThemes {
            let label = "\(theme.title)  (\(theme.sourceBadge), \(theme.typeBadge))"
            uiThemePopup.addItem(withTitle: label)
            uiThemePopup.lastItem?.representedObject = themeSelectionIdentifier(for: theme)
        }
        isProgrammaticUIThemeSelection = false

        if let manualSelection,
           uiThemePopup.itemArray.contains(where: { ($0.representedObject as? String) == manualSelection }) {
            setUIThemePopupSelection(identifier: manualSelection)
        } else {
            if manualSelection != nil {
                uiThemeSelectionDirty = false
            }
            syncUIThemePopupSelectionFromModel()
        }
    }

    private func selectedUITheme() -> SpectraUITheme? {
        guard let raw = selectedUIThemeIdentifier() else { return nil }
        let parts = raw.components(separatedBy: "::")
        guard parts.count == 2, let source = SpectraUIThemeSource(rawValue: parts[0]) else { return nil }
        return SpectraThemeManager.shared.allUIThemes().first { $0.id == parts[1] && $0.source == source }
    }

    @objc private func previewSelectedUITheme(_ sender: Any?) {
        guard let theme = selectedUITheme() else { return }
        uiThemeSelectionDirty = false
        SpectraThemeManager.shared.preview(themeID: theme.id, source: theme.source)
    }

    @objc private func applySelectedUITheme(_ sender: Any?) {
        guard let theme = selectedUITheme() else { return }
        // clearPreview() is handled by AppDelegate's onChange handler AFTER config is written.
        // Calling it here (before writeAndReload) would trigger a KVO reentrant loop because
        // hasExplicitUIThemeSelection is still false at this point.
        uiThemeSelectionDirty = false

        var updates: [String: String] = [
            "spectra-ui-theme": theme.id,
            "spectra-ui-theme-source": theme.source.rawValue,
        ]

        let normalizedAppearance = SpectraThemeManager.normalizedAppearanceMode(
            SpectraConfig.uiAppearanceMode,
            themeKind: theme.kind
        )
        if normalizedAppearance != SpectraConfig.uiAppearanceMode {
            updates["spectra-ui-appearance"] = normalizedAppearance
            appearancePopup?.selectItem(withTitle: titleForAppearanceMode(normalizedAppearance))
        }

        configManager.writeAndReload(updates, scope: .ui)
    }

    @objc private func resetUIThemeSelection(_ sender: Any?) {
        // clearPreview() is handled by AppDelegate's onChange handler after config is written.
        uiThemeSelectionDirty = false
        configManager.writeAndReload([
            "spectra-ui-theme": "",
            "spectra-ui-theme-source": "",
            "spectra-ui-appearance": "auto",
            "spectra-appearance": "",
        ], scope: .ui)
        appearancePopup?.selectItem(withTitle: "Auto")
    }

    @objc private func importUIThemeFile(_ sender: Any?) {
        guard let win = window else { return }
        let panel = NSOpenPanel()
        panel.title = "Import VS Code Theme File"
        panel.allowedContentTypes = [.json, .plainText]
        panel.allowsOtherFileTypes = true
        panel.beginSheetModal(for: win) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let installedAt = ISO8601DateFormatter().string(from: Date())
                let theme = try SpectraThemeManager.shared.importTheme(from: url, installedAt: installedAt)
                self.uiThemeSelectionDirty = false
                self.rebuildUIThemePopup()
                self.setUIThemePopupSelection(identifier: self.themeSelectionIdentifier(for: theme))
                SpectraThemeManager.shared.preview(themeID: theme.id, source: theme.source)
            } catch {
                let alert = NSAlert(error: error)
                alert.beginSheetModal(for: win) { _ in }
            }
        }
    }

    @objc private func applySettings(_ sender: Any?) {
        var updates: [String: String] = [:]

        switch currentTab {
        case .general:
            updates["window-width"] = windowWidthField.stringValue
            updates["window-height"] = windowHeightField.stringValue

        case .appearance:
            let modeTitle = appearancePopup.titleOfSelectedItem ?? "Auto"
            let requestedAppearanceMode: String = {
                switch modeTitle {
                case "Light": return "light"
                case "Dark": return "dark"
                default: return "auto"
                }
            }()
            let explicitThemeKind: SpectraUIThemeKind? = SpectraConfig.hasExplicitUIThemeSelection ? SpectraThemeManager.shared.currentTheme.kind : nil
            let normalizedAppearanceMode = SpectraThemeManager.normalizedAppearanceMode(
                requestedAppearanceMode,
                themeKind: explicitThemeKind
            )
            updates["spectra-ui-appearance"] = normalizedAppearanceMode
            if normalizedAppearanceMode != requestedAppearanceMode {
                appearancePopup.selectItem(withTitle: titleForAppearanceMode(normalizedAppearanceMode))
            }
            if let theme = terminalThemePopup.titleOfSelectedItem {
                updates["theme"] = theme == "Follow Appearance" ? "" : theme
            }

            updates["background-opacity"] = String(format: "%.2f", opacitySlider.doubleValue)
            updates["background-blur"] = blurPopup.titleOfSelectedItem == "On" ? "true" : "false"

            updates["cursor-style"] = cursorPopup.titleOfSelectedItem ?? "block"
            updates["cursor-style-blink"] = cursorBlinkCheck.state == .on ? "true" : "false"

            updates["window-padding-x"] = paddingXField.stringValue
            updates["window-padding-y"] = paddingYField.stringValue
            switch paddingBalancePopup.titleOfSelectedItem ?? "Off" {
            case "On": updates["window-padding-balance"] = "true"
            case "Equal": updates["window-padding-balance"] = "equal"
            default: updates["window-padding-balance"] = "false"
            }

        case .font:
            if let family = fontFamilyPopup.titleOfSelectedItem, !family.isEmpty {
                updates["font-family"] = family
            }
            updates["font-size"] = fontSizeField.stringValue
        }

        configManager.writeAndReload(updates)
    }

    @objc private func importFromGhostty(_ sender: Any?) {
        guard let win = window else { return }
        guard SpectraConfig.canImportFromGhostty else {
            let paths = SpectraConfig.ghosttyConfigCandidates.map { $0.path }.joined(separator: "\n  ")
            let alert = NSAlert()
            alert.messageText = "Ghostty Config Not Found"
            alert.informativeText = "Searched:\n  \(paths)\n\nUse \"Import File…\" to select a config file manually."
            alert.beginSheetModal(for: win) { _ in }
            return
        }
        let alert = NSAlert()
        alert.messageText = "Import from Ghostty"
        alert.informativeText = "This will overwrite your current Spectra config with Ghostty's config. Continue?"
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: win) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            if SpectraConfig.importFromGhostty() {
                self?.configManager.reload()
                self?.invalidateTabsAfterExternalConfigReload()
            }
        }
    }

    @objc private func importFromFile(_ sender: Any?) {
        guard let win = window else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Config File"
        panel.allowedContentTypes = [.plainText, .data]
        panel.allowsOtherFileTypes = true
        panel.beginSheetModal(for: win) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            if SpectraConfig.importFrom(url: url) {
                self?.configManager.reload()
                self?.invalidateTabsAfterExternalConfigReload()
            }
        }
    }

    // MARK: - View Helpers

    private func makeStack() -> NSStackView {
        let s = NSStackView()
        s.orientation = .vertical; s.alignment = .leading; s.spacing = 12
        s.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    private func embedScrollableStack(_ stack: NSStackView) -> NSView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        documentView.addSubview(stack)

        // The OverlayPanel (.medium) uses auto-height: a shrink constraint
        // (height=0, priority 250) plus a max constraint (≤85%, required).
        // NSScrollView has no intrinsicContentSize, so the panel would collapse
        // without upward height pressure. This constraint makes the scroll view
        // prefer to be as tall as its content (priority 510 > shrink's 250),
        // but yields to the panel's max-height cap (required).
        let contentHeight = scrollView.heightAnchor.constraint(equalTo: stack.heightAnchor)
        contentHeight.priority = .init(rawValue: 510)

        NSLayoutConstraint.activate([
            contentHeight,
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        return scrollView
    }

    @discardableResult
    private func addField(to stack: NSStackView, label: String, value: String, placeholder: String = "") -> NSTextField {
        let row = NSStackView()
        row.orientation = .horizontal; row.spacing = 8
        let lbl = NSTextField(labelWithString: label)
        lbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        lbl.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(field)
        stack.addArrangedSubview(row)
        return field
    }

    @discardableResult
    private func addPopupRow(to stack: NSStackView, label: String, items: [String], selected: String) -> NSPopUpButton {
        let row = NSStackView()
        row.orientation = .horizontal; row.spacing = 8
        let lbl = NSTextField(labelWithString: label)
        lbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        lbl.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        let popup = NSPopUpButton()
        popup.addItems(withTitles: items)
        popup.selectItem(withTitle: selected)
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(popup)
        stack.addArrangedSubview(row)
        return popup
    }

    private func addNote(to stack: NSStackView, text: String) {
        if let last = stack.arrangedSubviews.last {
            stack.setCustomSpacing(2, after: last)
        }
        let note = NSTextField(labelWithString: text)
        note.font = .systemFont(ofSize: 10)
        note.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(note)
    }

    private func addSectionHeader(to stack: NSStackView, title: String) {
        if let last = stack.arrangedSubviews.last {
            stack.setCustomSpacing(20, after: last)
        }
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(label)
        stack.setCustomSpacing(6, after: label)
    }

    private func addApplyButton(to stack: NSStackView) {
        let row = NSStackView()
        row.orientation = .horizontal; row.spacing = 8
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let btn = NSButton(title: "Apply", target: self, action: #selector(applySettings(_:)))
        btn.bezelStyle = .rounded; btn.keyEquivalent = "\r"
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(btn)
        stack.addArrangedSubview(row)
    }
}

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
