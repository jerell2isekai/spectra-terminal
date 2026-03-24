import AppKit

/// macOS native Settings window with toolbar tabs.
class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private var configManager: ConfigManager
    private var currentTab: Tab = .general
    private let containerView = NSView()

    // Controls that need updating
    private var fontFamilyField: NSTextField!
    private var fontSizeField: NSTextField!
    private var fontSizeStepper: NSStepper!
    private var lineHeightField: NSTextField!
    private var themeField: NSTextField!
    private var opacitySlider: NSSlider!
    private var opacityLabel: NSTextField!
    private var cursorPopup: NSPopUpButton!
    private var cursorBlinkCheck: NSButton!
    private var paddingXField: NSTextField!
    private var paddingYField: NSTextField!
    private var shellField: NSTextField!
    private var scrollbackField: NSTextField!
    private var confirmCloseCheck: NSButton!

    enum Tab: String, CaseIterable {
        case general = "General"
        case appearance = "Appearance"
        case font = "Font"
    }

    init(configManager: ConfigManager) {
        self.configManager = configManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Toolbar

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(Tab.general.rawValue)
        window?.toolbar = toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = itemIdentifier.rawValue
        item.target = self
        item.action = #selector(switchTab(_:))

        switch itemIdentifier.rawValue {
        case "General":
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General")
        case "Appearance":
            item.image = NSImage(systemSymbolName: "paintbrush", accessibilityDescription: "Appearance")
        case "Font":
            item.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Font")
        default: break
        }
        return item
    }

    @objc private func switchTab(_ sender: NSToolbarItem) {
        guard let tab = Tab(rawValue: sender.itemIdentifier.rawValue) else { return }
        showTab(tab)
    }

    // MARK: - Tab Content

    private func showTab(_ tab: Tab) {
        currentTab = tab
        containerView.subviews.forEach { $0.removeFromSuperview() }
        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)

        switch tab {
        case .general:  buildGeneralTab()
        case .appearance: buildAppearanceTab()
        case .font:     buildFontTab()
        }
    }

    // MARK: - General Tab

    private func buildGeneralTab() {
        let config = configManager.config
        let stack = makeStack()

        shellField = addLabeledTextField(to: stack, label: "Shell:", value: config.general.shell,
                                         placeholder: "Default ($SHELL)")
        scrollbackField = addLabeledTextField(to: stack, label: "Scrollback lines:",
                                              value: "\(config.general.scrollbackLines)")
        confirmCloseCheck = addCheckbox(to: stack, label: "Confirm before closing terminal",
                                        checked: config.general.confirmClose)

        addSpacer(to: stack)
        addApplyButton(to: stack)
        containerView.addSubview(stack)
        pinStack(stack)
    }

    // MARK: - Appearance Tab

    private func buildAppearanceTab() {
        let config = configManager.config
        let stack = makeStack()

        themeField = addLabeledTextField(to: stack, label: "Theme:", value: config.appearance.theme,
                                         placeholder: "e.g. catppuccin-mocha")

        // Opacity
        let opacityRow = NSStackView()
        opacityRow.orientation = .horizontal
        opacityRow.spacing = 8
        let opacityLbl = NSTextField(labelWithString: "Background Opacity:")
        opacityLbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        opacitySlider = NSSlider(value: config.appearance.backgroundOpacity,
                                 minValue: 0.1, maxValue: 1.0,
                                 target: self, action: #selector(opacitySliderChanged(_:)))
        opacityLabel = NSTextField(labelWithString: String(format: "%.0f%%", config.appearance.backgroundOpacity * 100))
        opacityLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        opacityRow.addArrangedSubview(opacityLbl)
        opacityRow.addArrangedSubview(opacitySlider)
        opacityRow.addArrangedSubview(opacityLabel)
        stack.addArrangedSubview(opacityRow)

        // Cursor
        let cursorRow = NSStackView()
        cursorRow.orientation = .horizontal
        cursorRow.spacing = 8
        let cursorLbl = NSTextField(labelWithString: "Cursor Style:")
        cursorLbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        cursorPopup = NSPopUpButton()
        cursorPopup.addItems(withTitles: ["block", "bar", "underline"])
        cursorPopup.selectItem(withTitle: config.cursor.style)
        cursorBlinkCheck = NSButton(checkboxWithTitle: "Blink", target: nil, action: nil)
        cursorBlinkCheck.state = config.cursor.blink ? .on : .off
        cursorRow.addArrangedSubview(cursorLbl)
        cursorRow.addArrangedSubview(cursorPopup)
        cursorRow.addArrangedSubview(cursorBlinkCheck)
        stack.addArrangedSubview(cursorRow)

        // Padding
        paddingXField = addLabeledTextField(to: stack, label: "Padding X:",
                                            value: "\(config.appearance.windowPaddingX)")
        paddingYField = addLabeledTextField(to: stack, label: "Padding Y:",
                                            value: "\(config.appearance.windowPaddingY)")

        addSpacer(to: stack)
        addApplyButton(to: stack)
        containerView.addSubview(stack)
        pinStack(stack)
    }

    // MARK: - Font Tab

    private func buildFontTab() {
        let config = configManager.config
        let stack = makeStack()

        fontFamilyField = addLabeledTextField(to: stack, label: "Font Family:",
                                              value: config.font.family,
                                              placeholder: "e.g. JetBrains Mono")

        // Size with stepper
        let sizeRow = NSStackView()
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 8
        let sizeLbl = NSTextField(labelWithString: "Font Size:")
        sizeLbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        fontSizeField = NSTextField(string: "\(Int(config.font.size))")
        fontSizeField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        fontSizeStepper = NSStepper()
        fontSizeStepper.minValue = 6
        fontSizeStepper.maxValue = 72
        fontSizeStepper.integerValue = Int(config.font.size)
        fontSizeStepper.target = self
        fontSizeStepper.action = #selector(fontSizeStepperChanged(_:))
        sizeRow.addArrangedSubview(sizeLbl)
        sizeRow.addArrangedSubview(fontSizeField)
        sizeRow.addArrangedSubview(fontSizeStepper)
        stack.addArrangedSubview(sizeRow)

        lineHeightField = addLabeledTextField(to: stack, label: "Line Height:",
                                              value: "\(config.font.lineHeight)")

        // Font preview
        let preview = NSTextField(labelWithString: "AaBbCcDdEeFf 0123456789 ~!@#$%")
        if !config.font.family.isEmpty {
            preview.font = NSFont(name: config.font.family, size: CGFloat(config.font.size))
                ?? NSFont.monospacedSystemFont(ofSize: CGFloat(config.font.size), weight: .regular)
        } else {
            preview.font = NSFont.monospacedSystemFont(ofSize: CGFloat(config.font.size), weight: .regular)
        }
        preview.alignment = .center
        stack.addArrangedSubview(preview)

        addSpacer(to: stack)
        addApplyButton(to: stack)
        containerView.addSubview(stack)
        pinStack(stack)
    }

    // MARK: - Actions

    @objc private func opacitySliderChanged(_ sender: NSSlider) {
        opacityLabel.stringValue = String(format: "%.0f%%", sender.doubleValue * 100)
    }

    @objc private func fontSizeStepperChanged(_ sender: NSStepper) {
        fontSizeField.stringValue = "\(sender.integerValue)"
    }

    @objc private func applySettings(_ sender: Any?) {
        var config = configManager.config

        switch currentTab {
        case .general:
            config.general.shell = shellField.stringValue
            config.general.scrollbackLines = Int(scrollbackField.stringValue) ?? config.general.scrollbackLines
            config.general.confirmClose = confirmCloseCheck.state == .on

        case .appearance:
            config.appearance.theme = themeField.stringValue
            config.appearance.backgroundOpacity = opacitySlider.doubleValue
            config.cursor.style = cursorPopup.titleOfSelectedItem ?? "block"
            config.cursor.blink = cursorBlinkCheck.state == .on
            config.appearance.windowPaddingX = Int(paddingXField.stringValue) ?? 0
            config.appearance.windowPaddingY = Int(paddingYField.stringValue) ?? 0

        case .font:
            config.font.family = fontFamilyField.stringValue
            config.font.size = Double(fontSizeField.stringValue) ?? config.font.size
            config.font.lineHeight = Double(lineHeightField.stringValue) ?? config.font.lineHeight
        }

        configManager.update(config)
    }

    // MARK: - View Helpers

    private func makeStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func pinStack(_ stack: NSStackView) {
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: containerView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor),
        ])
    }

    @discardableResult
    private func addLabeledTextField(to stack: NSStackView, label: String,
                                     value: String, placeholder: String = "") -> NSTextField {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
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

    private func addCheckbox(to stack: NSStackView, label: String, checked: Bool) -> NSButton {
        let check = NSButton(checkboxWithTitle: label, target: nil, action: nil)
        check.state = checked ? .on : .off
        stack.addArrangedSubview(check)
        return check
    }

    private func addSpacer(to stack: NSStackView) {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(spacer)
    }

    private func addApplyButton(to stack: NSStackView) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let applyBtn = NSButton(title: "Apply", target: self, action: #selector(applySettings(_:)))
        applyBtn.bezelStyle = .rounded
        applyBtn.keyEquivalent = "\r"
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(applyBtn)
        stack.addArrangedSubview(row)
    }
}
