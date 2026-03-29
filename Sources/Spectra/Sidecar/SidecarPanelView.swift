import AppKit

/// The visual layout for the Agent Sidecar Panel.
///
/// Layout (top to bottom):
/// - Title bar: "Agent Sidecar"
/// - Terminal selector: NSPopUpButton
/// - Model status indicators: per-model colored dots
/// - Action buttons: Review Terminal / Inject into Terminal
/// - Review results: per-model collapsible sections with streaming NSTextView
final class SidecarPanelView: NSView {

    // MARK: - UI Elements

    let terminalSelector = NSPopUpButton(frame: .zero, pullsDown: false)
    let grabButton = NSButton(title: "Grab Context", target: nil, action: nil)
    let injectButton = NSButton(title: "Inject into Terminal", target: nil, action: nil)
    let inputField = NSTextField()
    let sendButton = NSButton(title: "Send", target: nil, action: nil)
    private let contextPreviewLabel = NSTextField(wrappingLabelWithString: "")

    private let titleLabel = NSTextField(labelWithString: "Agent Sidecar")
    private let modelStack = NSStackView()
    private var modelStatusViews: [ModelStatusView] = []
    private let resultsStack = NSStackView()
    private(set) var resultSections: [ReviewResultSection] = []
    private var equalHeightConstraints: [NSLayoutConstraint] = []
    private let emptyStatePlaceholder = NSTextField(labelWithString: "Enable at least one model to begin review")

    /// Called when user toggles a model checkbox. Parameters: (index, enabled).
    var onModelToggle: ((Int, Bool) -> Void)?

    // Debug log
    private let logTextView = NSTextView()

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Configuration

    /// Configure model status indicators with initial enabled state.
    func configureModels(_ models: [(name: String, displayName: String, enabled: Bool)]) {
        modelStatusViews.forEach { $0.removeFromSuperview() }
        modelStatusViews = models.enumerated().map { (i, m) in
            let view = ModelStatusView(displayName: m.displayName, enabled: m.enabled)
            view.onToggle = { [weak self] enabled in
                self?.onModelToggle?(i, enabled)
            }
            return view
        }
        modelStack.setViews(modelStatusViews, in: .leading)

        resultSections.forEach { $0.view.removeFromSuperview() }
        resultSections = models.map { ReviewResultSection(displayName: $0.displayName) }

        // Hide disabled models' result sections
        for (i, section) in resultSections.enumerated() {
            section.view.isHidden = !models[i].enabled
        }

        resultsStack.setViews(resultSections.map(\.view), in: .top)

        // Each result section fills width
        for section in resultSections {
            section.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                section.view.leadingAnchor.constraint(equalTo: resultsStack.leadingAnchor),
                section.view.trailingAnchor.constraint(equalTo: resultsStack.trailingAnchor),
            ])
        }

        updateEqualHeightConstraints()
    }

    /// Update model status indicator.
    func setModelStatus(_ index: Int, status: ModelStatusView.Status) {
        guard index < modelStatusViews.count else { return }
        modelStatusViews[index].status = status
    }

    /// Show/hide a model's result section.
    func setModelEnabled(_ index: Int, enabled: Bool) {
        guard index < resultSections.count else { return }
        resultSections[index].view.isHidden = !enabled
    }

    /// Enable or disable all model toggle checkboxes (used during review).
    func setToggleEnabled(_ enabled: Bool) {
        for view in modelStatusViews {
            view.setCheckboxEnabled(enabled)
        }
    }

    /// Rebuild equal-height constraints for visible result sections only.
    func updateEqualHeightConstraints() {
        NSLayoutConstraint.deactivate(equalHeightConstraints)
        equalHeightConstraints.removeAll()

        let visibleSections = resultSections.filter { !$0.view.isHidden }

        if visibleSections.isEmpty {
            emptyStatePlaceholder.isHidden = false
            resultsStack.isHidden = true
        } else {
            emptyStatePlaceholder.isHidden = true
            resultsStack.isHidden = false
            if visibleSections.count > 1 {
                for i in 1..<visibleSections.count {
                    let c = visibleSections[i].view.heightAnchor.constraint(
                        equalTo: visibleSections[0].view.heightAnchor
                    )
                    equalHeightConstraints.append(c)
                }
                NSLayoutConstraint.activate(equalHeightConstraints)
            }
        }
    }

    /// Update terminal selector with available terminals.
    func updateTerminalList(_ titles: [String]) {
        terminalSelector.removeAllItems()
        terminalSelector.addItems(withTitles: titles)
    }

    /// Show captured context preview and enable input.
    func showContextCaptured(charCount: Int, preview: String) {
        contextPreviewLabel.stringValue = "✓ Captured \(charCount) chars: \(preview)"
        contextPreviewLabel.isHidden = false
        inputField.isEnabled = true
        sendButton.isEnabled = true
        inputField.window?.makeFirstResponder(inputField)
    }

    /// Reset context state.
    func clearContext() {
        contextPreviewLabel.isHidden = true
        inputField.stringValue = ""
        inputField.isEnabled = false
        sendButton.isEnabled = false
    }

    /// Append a timestamped log line to the debug log area.
    func appendLog(_ message: String) {
        let ts = Self.logDateFormatter.string(from: Date())
        let line = "[\(ts)] \(message)\n"
        logTextView.textStorage?.append(NSAttributedString(
            string: line,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))
        logTextView.scrollToEndOfDocument(nil)
    }

    private static let logDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - Layout

    private func setupUI() {
        // Title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        // Terminal selector
        terminalSelector.controlSize = .small

        // Model status stack
        modelStack.orientation = .vertical
        modelStack.alignment = .leading
        modelStack.spacing = 4

        // Grab Context button
        grabButton.bezelStyle = .rounded
        grabButton.controlSize = .regular
        grabButton.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)
        grabButton.imagePosition = .imageLeading

        // Context preview (shows after grab)
        contextPreviewLabel.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        contextPreviewLabel.textColor = .tertiaryLabelColor
        contextPreviewLabel.maximumNumberOfLines = 2
        contextPreviewLabel.isHidden = true

        // User input field + send
        inputField.placeholderString = "Ask about the captured context..."
        inputField.font = .systemFont(ofSize: 12)
        inputField.controlSize = .regular
        inputField.isEnabled = false

        sendButton.bezelStyle = .rounded
        sendButton.controlSize = .regular
        sendButton.image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: nil)
        sendButton.imagePosition = .imageOnly
        sendButton.isEnabled = false

        let inputRow = NSStackView(views: [inputField, sendButton])
        inputRow.orientation = .horizontal
        inputRow.spacing = 4
        inputRow.translatesAutoresizingMaskIntoConstraints = false

        // Inject button
        injectButton.bezelStyle = .rounded
        injectButton.controlSize = .small
        injectButton.image = NSImage(systemSymbolName: "arrow.left", accessibilityDescription: nil)
        injectButton.imagePosition = .imageLeading
        injectButton.isEnabled = false

        let buttonStack = NSStackView(views: [grabButton, contextPreviewLabel, inputRow, injectButton])
        buttonStack.orientation = .vertical
        buttonStack.alignment = .leading
        buttonStack.spacing = 6

        // Results area — plain container, no outer scroll.
        // Each ReviewResultSection owns its own scrollable body.
        resultsStack.orientation = .vertical
        resultsStack.alignment = .leading
        resultsStack.spacing = 8
        resultsStack.translatesAutoresizingMaskIntoConstraints = false

        // Empty state placeholder (shown when all models are disabled)
        emptyStatePlaceholder.font = .systemFont(ofSize: 12)
        emptyStatePlaceholder.textColor = .tertiaryLabelColor
        emptyStatePlaceholder.alignment = .center
        emptyStatePlaceholder.isHidden = true
        emptyStatePlaceholder.translatesAutoresizingMaskIntoConstraints = false

        // Separator
        let separator = NSBox()
        separator.boxType = .separator

        // Log view setup
        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.isRichText = false
        logTextView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        logTextView.textColor = .secondaryLabelColor
        logTextView.backgroundColor = .clear
        logTextView.isVerticallyResizable = true
        logTextView.isHorizontallyResizable = false
        logTextView.textContainer?.widthTracksTextView = true
        logTextView.textContainer?.lineFragmentPadding = 4

        let logScrollView = NSScrollView()
        logScrollView.documentView = logTextView
        logScrollView.hasVerticalScroller = true
        logScrollView.hasHorizontalScroller = false
        logScrollView.drawsBackground = false
        logScrollView.translatesAutoresizingMaskIntoConstraints = false

        let logLabel = NSTextField(labelWithString: "Log")
        logLabel.font = .systemFont(ofSize: 10, weight: .medium)
        logLabel.textColor = .tertiaryLabelColor

        let logSeparator = NSBox()
        logSeparator.boxType = .separator

        // Main stack
        let topStack = NSStackView(views: [
            titleLabel, terminalSelector, modelStack, buttonStack, separator
        ])
        topStack.orientation = .vertical
        topStack.alignment = .leading
        topStack.spacing = 10
        topStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 8, right: 12)
        topStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(topStack)
        addSubview(resultsStack)
        addSubview(emptyStatePlaceholder)
        addSubview(logSeparator)
        addSubview(logLabel)
        addSubview(logScrollView)

        logSeparator.translatesAutoresizingMaskIntoConstraints = false
        logLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: topAnchor),
            topStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            topStack.trailingAnchor.constraint(equalTo: trailingAnchor),

            // Results area — fills space between topStack and log
            resultsStack.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 4),
            resultsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            resultsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            // Empty state placeholder — same position as resultsStack
            emptyStatePlaceholder.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 20),
            emptyStatePlaceholder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            emptyStatePlaceholder.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            // Log separator + label — pinned below both resultsStack and emptyStatePlaceholder
            logSeparator.topAnchor.constraint(greaterThanOrEqualTo: resultsStack.bottomAnchor, constant: 4),
            logSeparator.topAnchor.constraint(greaterThanOrEqualTo: emptyStatePlaceholder.bottomAnchor, constant: 4),
            logSeparator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            logSeparator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            logLabel.topAnchor.constraint(equalTo: logSeparator.bottomAnchor, constant: 4),
            logLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            // Log scroll view — bottom portion
            logScrollView.topAnchor.constraint(equalTo: logLabel.bottomAnchor, constant: 2),
            logScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            logScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            logScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            logScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),

            terminalSelector.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            grabButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            inputRow.leadingAnchor.constraint(equalTo: topStack.leadingAnchor, constant: 12),
            inputRow.trailingAnchor.constraint(equalTo: topStack.trailingAnchor, constant: -12),
            sendButton.widthAnchor.constraint(equalToConstant: 32),
        ])
    }
}

// MARK: - Model Status View

final class ModelStatusView: NSView {
    enum Status {
        case idle, connecting, streaming, done(seconds: Double), error(String), unavailable
    }

    var status: Status = .idle { didSet { updateDisplay() } }
    private let checkbox: NSButton
    var onToggle: ((Bool) -> Void)?
    private let dot = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
    private let label: NSTextField

    init(displayName: String, enabled: Bool = true) {
        checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        label = NSTextField(labelWithString: displayName)
        super.init(frame: .zero)

        checkbox.state = enabled ? .on : .off
        checkbox.target = self
        checkbox.action = #selector(checkboxToggled)
        checkbox.controlSize = .small

        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [checkbox, dot, label])
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])
        updateDisplay()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setCheckboxEnabled(_ enabled: Bool) {
        checkbox.isEnabled = enabled
    }

    @objc private func checkboxToggled(_ sender: NSButton) {
        onToggle?(sender.state == .on)
    }

    private func updateDisplay() {
        switch status {
        case .idle:
            dot.layer?.backgroundColor = NSColor.systemGray.cgColor
        case .connecting:
            dot.layer?.backgroundColor = NSColor.systemYellow.cgColor
        case .streaming:
            dot.layer?.backgroundColor = NSColor.systemBlue.cgColor
        case .done:
            dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        case .error:
            dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        case .unavailable:
            dot.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
        }
    }
}

// MARK: - Review Result Section

/// A section showing one model's review output with its own scroll view.
final class ReviewResultSection {
    let view: NSView
    let textView: NSTextView
    private let headerButton: NSButton
    private let usageLabel: NSTextField
    private let textScrollView: NSScrollView
    private let placeholderText = "Debug placeholder: result view is rendering"

    init(displayName: String) {
        headerButton = NSButton(title: "▾ \(displayName)", target: nil, action: nil)
        headerButton.bezelStyle = .inline
        headerButton.font = .systemFont(ofSize: 12, weight: .medium)
        headerButton.alignment = .left
        headerButton.translatesAutoresizingMaskIntoConstraints = false

        usageLabel = NSTextField(labelWithString: "")
        usageLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        usageLabel.textColor = .tertiaryLabelColor
        usageLabel.translatesAutoresizingMaskIntoConstraints = false

        let sectionSeparator = NSBox()
        sectionSeparator.boxType = .separator
        sectionSeparator.translatesAutoresizingMaskIntoConstraints = false

        // Each agent owns its own scrollable result body. Keep the recipe minimal:
        // a plain NSTextView inside a plain NSScrollView, with no layer-backed
        // decoration and no extra container tricks.
        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 4

        textScrollView = NSScrollView()
        textScrollView.documentView = textView
        textScrollView.hasVerticalScroller = true
        textScrollView.hasHorizontalScroller = false
        textScrollView.autohidesScrollers = true
        textScrollView.drawsBackground = false
        textScrollView.translatesAutoresizingMaskIntoConstraints = false

        // Container view
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sectionSeparator)
        container.addSubview(headerButton)
        container.addSubview(usageLabel)
        container.addSubview(textScrollView)

        NSLayoutConstraint.activate([
            sectionSeparator.topAnchor.constraint(equalTo: container.topAnchor),
            sectionSeparator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sectionSeparator.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            headerButton.topAnchor.constraint(equalTo: sectionSeparator.bottomAnchor, constant: 4),
            headerButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            usageLabel.topAnchor.constraint(equalTo: headerButton.bottomAnchor, constant: 2),
            usageLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            usageLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            textScrollView.topAnchor.constraint(equalTo: usageLabel.bottomAnchor, constant: 4),
            textScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textScrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            textScrollView.heightAnchor.constraint(equalToConstant: 180),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])

        view = container
    }

    /// Append streaming text delta.
    func appendText(_ text: String) {
        if textView.string == placeholderText {
            textView.string = ""
            textView.textColor = .labelColor
        }
        textView.textStorage?.append(NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
        ))
        if let textContainer = textView.textContainer,
           let layoutManager = textView.layoutManager {
            layoutManager.ensureLayout(for: textContainer)
        }
        let endRange = NSRange(location: (textView.string as NSString).length, length: 0)
        textView.scrollRangeToVisible(endRange)
    }

    /// Clear content for new review.
    func clear() {
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: placeholderText,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))
        textView.textColor = .secondaryLabelColor
        usageLabel.stringValue = ""
        let base = headerButton.title.components(separatedBy: " (").first ?? headerButton.title
        headerButton.title = base
    }

    /// Set usage info after completion.
    func setUsage(_ usage: PiTokenUsage, elapsed: TimeInterval) {
        usageLabel.stringValue = "\(usage.inputTokens) in / \(usage.outputTokens) out · \(String(format: "%.1f", elapsed))s"
        let base = headerButton.title.components(separatedBy: " (").first ?? headerButton.title
        headerButton.title = "\(base) (\(String(format: "%.1f", elapsed))s)"
    }

    func setError(_ message: String) {
        appendText("\n⚠️ Error: \(message)\n")
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
