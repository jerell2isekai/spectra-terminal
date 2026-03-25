import AppKit

/// A reusable overlay panel that presents content inside the main window.
/// Replaces floating windows and tab-based previews with an in-window modal experience.
class OverlayPanel: NSView {

    enum Size {
        /// 85% width, 90% height — file preview, diff
        case large
        /// Fixed 520pt width, auto height up to 80% — settings
        case medium
        /// Fixed 400pt width, auto height — about
        case small
    }

    private let backdrop = NSView()
    private let panelView: NSVisualEffectView
    private let headerView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton: NSButton
    private let separator = NSBox()
    private let contentContainer = NSView()

    private var panelWidthConstraint: NSLayoutConstraint?
    private var panelCenterYConstraint: NSLayoutConstraint?

    private var eventMonitor: Any?
    private let panelSize: Size

    /// Internal cleanup callback (set by WorkspaceViewController).
    var internalDismissHandler: (() -> Void)?
    /// Public callback for consumers.
    var onDismiss: (() -> Void)?

    init(title: String, size: Size = .large) {
        self.panelSize = size

        panelView = NSVisualEffectView()
        panelView.material = .windowBackground
        panelView.blendingMode = .withinWindow
        panelView.state = .active
        panelView.wantsLayer = true
        panelView.layer?.cornerRadius = 12
        panelView.layer?.masksToBounds = true

        closeButton = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill",
                                               accessibilityDescription: "Close")!,
                                target: nil, action: nil)

        super.init(frame: .zero)

        closeButton.target = self
        closeButton.action = #selector(dismissAction)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton.isBordered = false
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.setContentHuggingPriority(.required, for: .horizontal)

        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        removeKeyMonitor()
    }

    // MARK: - Setup

    private func setupViews() {
        // Backdrop
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(backdropClicked))
        backdrop.addGestureRecognizer(clickGesture)

        // Panel
        panelView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panelView)

        // Header
        headerView.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(headerView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(closeButton)

        // Separator line
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(separator)

        // Content container
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(contentContainer)

        // Backdrop fills parent
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Panel centered
        let centerY = panelView.centerYAnchor.constraint(equalTo: centerYAnchor)
        panelCenterYConstraint = centerY
        NSLayoutConstraint.activate([
            panelView.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerY,
        ])

        // Size constraints based on mode
        switch panelSize {
        case .large:
            NSLayoutConstraint.activate([
                panelView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.85),
                panelView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.9),
            ])
        case .medium:
            let w = panelView.widthAnchor.constraint(equalToConstant: 520)
            panelWidthConstraint = w
            let shrink = panelView.heightAnchor.constraint(equalToConstant: 0)
            shrink.priority = .defaultLow
            NSLayoutConstraint.activate([
                w,
                panelView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, multiplier: 0.85),
                shrink,
            ])
        case .small:
            let w = panelView.widthAnchor.constraint(equalToConstant: 400)
            panelWidthConstraint = w
            let shrink = panelView.heightAnchor.constraint(equalToConstant: 0)
            shrink.priority = .defaultLow
            NSLayoutConstraint.activate([
                w,
                panelView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, multiplier: 0.7),
                shrink,
            ])
        }

        // Header layout
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: panelView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),

            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
        ])

        // Separator
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
        ])

        // Content container fills remaining space
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: separator.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: panelView.bottomAnchor),
        ])
    }

    // MARK: - Content

    /// Embed a content view inside the panel's content area.
    func setContent(_ view: NSView) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
        ])
    }

    /// Add a toolbar view (e.g. segmented control) to the header, placed after the title.
    func setHeaderToolbar(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
        ])
    }

    // MARK: - Show / Dismiss

    func show(in parentView: NSView) {
        translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parentView.topAnchor),
            bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
            leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
        ])

        // Initial state for animation
        alphaValue = 0
        panelView.alphaValue = 0
        panelCenterYConstraint?.constant = 20
        layoutSubtreeIfNeeded()

        // Animate in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            self.alphaValue = 1
            self.panelView.alphaValue = 1
            self.panelCenterYConstraint?.constant = 0
            self.layoutSubtreeIfNeeded()
        }

        installKeyMonitor()
    }

    func dismiss() {
        removeKeyMonitor()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            self.alphaValue = 0
            self.panelCenterYConstraint?.constant = 20
            self.layoutSubtreeIfNeeded()
        }, completionHandler: {
            self.removeFromSuperview()
            self.internalDismissHandler?()
            self.onDismiss?()
        })
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.superview != nil else { return event }
            // ESC
            if event.keyCode == 53 {
                self.dismiss()
                return nil
            }
            // Cmd+W
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w" {
                self.dismiss()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Actions

    @objc private func dismissAction() {
        dismiss()
    }

    @objc private func backdropClicked(_ sender: NSClickGestureRecognizer) {
        let location = sender.location(in: self)
        // Only dismiss if click is on backdrop, not on panel
        if !panelView.frame.contains(location) {
            dismiss()
        }
    }
}
