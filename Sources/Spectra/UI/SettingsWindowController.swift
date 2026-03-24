import AppKit

/// macOS native Settings window with toolbar tabs.
class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private var configManager: ConfigManager
    private var currentTab: Tab = .general
    private let containerView = NSView()

    private var fontFamilyField: NSTextField!
    private var fontSizeField: NSTextField!
    private var fontSizeStepper: NSStepper!
    private var themeField: NSTextField!
    private var opacitySlider: NSSlider!
    private var opacityLabel: NSTextField!
    private var cursorPopup: NSPopUpButton!
    private var cursorBlinkCheck: NSButton!
    private var paddingXField: NSTextField!
    private var paddingYField: NSTextField!
    private var appearancePopup: NSPopUpButton!
    private var shellField: NSTextField!
    private var scrollbackField: NSTextField!
    private var windowWidthField: NSTextField!
    private var windowHeightField: NSTextField!

    enum Tab: String, CaseIterable {
        case general = "General"
        case appearance = "Appearance"
        case font = "Font"
    }

    init(configManager: ConfigManager) {
        self.configManager = configManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Spectra Settings"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.contentView = containerView
        setupToolbar()
        showTab(.general)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Toolbar

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(Tab.general.rawValue)
        window?.toolbar = toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map { .init($0.rawValue) }
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map { .init($0.rawValue) }
    }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map { .init($0.rawValue) }
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = id.rawValue
        item.target = self
        item.action = #selector(switchTab(_:))
        switch id.rawValue {
        case "General":    item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        case "Appearance": item.image = NSImage(systemSymbolName: "paintbrush", accessibilityDescription: nil)
        case "Font":       item.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
        default: break
        }
        return item
    }

    @objc private func switchTab(_ sender: NSToolbarItem) {
        guard let tab = Tab(rawValue: sender.itemIdentifier.rawValue) else { return }
        showTab(tab)
    }

    private func showTab(_ tab: Tab) {
        currentTab = tab
        containerView.subviews.forEach { $0.removeFromSuperview() }
        window?.toolbar?.selectedItemIdentifier = .init(tab.rawValue)
        switch tab {
        case .general:    buildGeneralTab()
        case .appearance: buildAppearanceTab()
        case .font:       buildFontTab()
        }
    }

    // MARK: - Read config helpers

    private func cfg(_ key: String, default d: String = "") -> String {
        SpectraConfig.read(key, default: d)
    }

    // MARK: - General Tab

    private func buildGeneralTab() {
        let stack = makeStack()

        shellField = addField(to: stack, label: "Shell:", value: cfg("command"),
                              placeholder: "Default ($SHELL)")
        scrollbackField = addField(to: stack, label: "Scrollback:", value: cfg("scrollback-limit", default: "10000"))
        windowWidthField = addField(to: stack, label: "Window Width (cols):", value: cfg("window-width", default: "120"))
        windowHeightField = addField(to: stack, label: "Window Height (rows):", value: cfg("window-height", default: "36"))

        stack.addArrangedSubview(NSView()) // separator

        // Import buttons
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

        addSpacer(to: stack)
        addApplyButton(to: stack)
        containerView.addSubview(stack)
        pinStack(stack)
    }

    // MARK: - Appearance Tab

    private func buildAppearanceTab() {
        let stack = makeStack()

        // Appearance Mode (Light / Dark / System)
        let modeRow = NSStackView()
        modeRow.orientation = .horizontal; modeRow.spacing = 8
        let modeLbl = NSTextField(labelWithString: "Appearance:")
        modeLbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        modeLbl.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        appearancePopup = NSPopUpButton()
        appearancePopup.addItems(withTitles: ["System", "Light", "Dark"])
        let currentMode = cfg("spectra-appearance", default: "system")
        switch currentMode {
        case "light": appearancePopup.selectItem(withTitle: "Light")
        case "dark":  appearancePopup.selectItem(withTitle: "Dark")
        default:      appearancePopup.selectItem(withTitle: "System")
        }
        modeRow.addArrangedSubview(modeLbl)
        modeRow.addArrangedSubview(appearancePopup)
        stack.addArrangedSubview(modeRow)

        themeField = addField(to: stack, label: "Theme:", value: cfg("theme"),
                              placeholder: "e.g. catppuccin-mocha")

        // Opacity
        let opacity = Double(cfg("background-opacity", default: "1")) ?? 1.0
        let opacityRow = NSStackView()
        opacityRow.orientation = .horizontal; opacityRow.spacing = 8
        let lbl = NSTextField(labelWithString: "Background Opacity:")
        lbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        opacitySlider = NSSlider(value: opacity, minValue: 0.1, maxValue: 1.0,
                                 target: self, action: #selector(opacityChanged(_:)))
        opacityLabel = NSTextField(labelWithString: String(format: "%.0f%%", opacity * 100))
        opacityLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        opacityRow.addArrangedSubview(lbl)
        opacityRow.addArrangedSubview(opacitySlider)
        opacityRow.addArrangedSubview(opacityLabel)
        stack.addArrangedSubview(opacityRow)

        // Cursor
        let cursorRow = NSStackView()
        cursorRow.orientation = .horizontal; cursorRow.spacing = 8
        let cLbl = NSTextField(labelWithString: "Cursor Style:")
        cLbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        cursorPopup = NSPopUpButton()
        cursorPopup.addItems(withTitles: ["block", "bar", "underline"])
        cursorPopup.selectItem(withTitle: cfg("cursor-style", default: "block"))
        cursorBlinkCheck = NSButton(checkboxWithTitle: "Blink", target: nil, action: nil)
        cursorBlinkCheck.state = cfg("cursor-style-blink", default: "true") == "true" ? .on : .off
        cursorRow.addArrangedSubview(cLbl)
        cursorRow.addArrangedSubview(cursorPopup)
        cursorRow.addArrangedSubview(cursorBlinkCheck)
        stack.addArrangedSubview(cursorRow)

        paddingXField = addField(to: stack, label: "Padding X:", value: cfg("window-padding-x", default: "0"))
        paddingYField = addField(to: stack, label: "Padding Y:", value: cfg("window-padding-y", default: "0"))

        addSpacer(to: stack)
        addApplyButton(to: stack)
        containerView.addSubview(stack)
        pinStack(stack)
    }

    // MARK: - Font Tab

    private func buildFontTab() {
        let stack = makeStack()

        fontFamilyField = addField(to: stack, label: "Font Family:", value: cfg("font-family"),
                                   placeholder: "e.g. JetBrains Mono")

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

        // Preview
        let family = cfg("font-family")
        let previewFont = family.isEmpty
            ? NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
            : NSFont(name: family, size: CGFloat(size))
                ?? NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
        let preview = NSTextField(labelWithString: "AaBbCcDdEeFf 0123456789 ~!@#$%")
        preview.font = previewFont
        preview.alignment = .center
        stack.addArrangedSubview(preview)

        addSpacer(to: stack)
        addApplyButton(to: stack)
        containerView.addSubview(stack)
        pinStack(stack)
    }

    // MARK: - Actions

    @objc private func opacityChanged(_ sender: NSSlider) {
        opacityLabel.stringValue = String(format: "%.0f%%", sender.doubleValue * 100)
    }

    @objc private func sizeStepperChanged(_ sender: NSStepper) {
        fontSizeField.stringValue = "\(sender.integerValue)"
    }

    @objc private func applySettings(_ sender: Any?) {
        var updates: [String: String] = [:]

        switch currentTab {
        case .general:
            let shell = shellField.stringValue.trimmingCharacters(in: .whitespaces)
            if !shell.isEmpty { updates["command"] = shell }
            updates["scrollback-limit"] = scrollbackField.stringValue
            updates["window-width"] = windowWidthField.stringValue
            updates["window-height"] = windowHeightField.stringValue

        case .appearance:
            let modeTitle = appearancePopup.titleOfSelectedItem ?? "System"
            switch modeTitle {
            case "Light": updates["spectra-appearance"] = "light"
            case "Dark":  updates["spectra-appearance"] = "dark"
            default:      updates["spectra-appearance"] = "system"
            }
            let theme = themeField.stringValue.trimmingCharacters(in: .whitespaces)
            if !theme.isEmpty { updates["theme"] = theme }
            updates["background-opacity"] = String(format: "%.2f", opacitySlider.doubleValue)
            updates["cursor-style"] = cursorPopup.titleOfSelectedItem ?? "block"
            updates["cursor-style-blink"] = cursorBlinkCheck.state == .on ? "true" : "false"
            updates["window-padding-x"] = paddingXField.stringValue
            updates["window-padding-y"] = paddingYField.stringValue

        case .font:
            let family = fontFamilyField.stringValue.trimmingCharacters(in: .whitespaces)
            if !family.isEmpty { updates["font-family"] = family }
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
                self?.showTab(self?.currentTab ?? .general)
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
                self?.showTab(self?.currentTab ?? .general)
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

    private func pinStack(_ s: NSStackView) {
        NSLayoutConstraint.activate([
            s.topAnchor.constraint(equalTo: containerView.topAnchor),
            s.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            s.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            s.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor),
        ])
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

    private func addSpacer(to stack: NSStackView) {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(v)
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
