import AppKit

// MARK: - Delegate

protocol PaneTabBarDelegate: AnyObject {
    func tabBar(_ tabBar: PaneTabBarView, didSelectTabAt index: Int)
    func tabBar(_ tabBar: PaneTabBarView, didCloseTabAt index: Int)
    func tabBarDidRequestNewTab(_ tabBar: PaneTabBarView)
}

// MARK: - Tab Bar

class PaneTabBarView: NSView {
    static let barHeight: CGFloat = 28

    weak var delegate: PaneTabBarDelegate?

    private let stackView = NSStackView()
    private let addButton: NSButton
    private var tabItems: [PaneTabItemView] = []

    override init(frame: NSRect) {
        addButton = NSButton(title: "+", target: nil, action: nil)
        super.init(frame: frame)

        wantsLayer = true

        addButton.target = self
        addButton.action = #selector(addButtonClicked)
        addButton.isBordered = false
        addButton.font = .systemFont(ofSize: 14, weight: .medium)
        addButton.contentTintColor = .secondaryLabelColor
        addButton.refusesFirstResponder = true
        addButton.widthAnchor.constraint(equalToConstant: 28).isActive = true

        stackView.orientation = .horizontal
        stackView.spacing = 0
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
    }

    func reload(titles: [String], activeIndex: Int) {
        // Fast path: same tab count — just update titles and active state
        if tabItems.count == titles.count {
            for (i, item) in tabItems.enumerated() {
                item.update(title: titles[i], isActive: i == activeIndex)
            }
            return
        }

        // Slow path: tab count changed — rebuild
        tabItems.forEach { $0.removeFromSuperview() }
        tabItems.removeAll()
        addButton.removeFromSuperview()

        for (i, title) in titles.enumerated() {
            let item = PaneTabItemView(title: title, index: i, isActive: i == activeIndex)
            item.onSelect = { [weak self] idx in
                guard let self else { return }
                self.delegate?.tabBar(self, didSelectTabAt: idx)
            }
            item.onClose = { [weak self] idx in
                guard let self else { return }
                self.delegate?.tabBar(self, didCloseTabAt: idx)
            }
            stackView.addArrangedSubview(item)
            tabItems.append(item)
        }

        stackView.addArrangedSubview(addButton)
    }

    @objc private func addButtonClicked() {
        delegate?.tabBarDidRequestNewTab(self)
    }
}

// MARK: - Tab Item

private class PaneTabItemView: NSView {
    let index: Int
    var isActive: Bool {
        didSet { updateAppearance() }
    }
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?

    private let titleLabel: NSTextField
    private let closeButton: NSButton
    private var isHovered = false

    init(title: String, index: Int, isActive: Bool) {
        self.index = index
        self.isActive = isActive

        titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton = NSButton(title: "\u{00D7}", target: nil, action: nil)
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 13)
        closeButton.refusesFirstResponder = true
        closeButton.alphaValue = 0

        super.init(frame: .zero)

        closeButton.target = self
        closeButton.action = #selector(closeClicked)

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(trackingArea)

        wantsLayer = true
        layer?.cornerRadius = 4

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            widthAnchor.constraint(lessThanOrEqualToConstant: 160),
            heightAnchor.constraint(equalToConstant: PaneTabBarView.barHeight - 4),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -2),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    /// Called by AppKit with the correct NSAppearance.current already set,
    /// so dynamic NSColor → CGColor resolution matches the view's appearance.
    override func updateLayer() {
        if isActive {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    func update(title: String, isActive: Bool) {
        titleLabel.stringValue = title
        self.isActive = isActive  // triggers updateAppearance via didSet
    }

    /// Update non-layer properties and schedule a layer redraw.
    private func updateAppearance() {
        if isActive {
            titleLabel.textColor = .labelColor
            closeButton.contentTintColor = .secondaryLabelColor
            closeButton.alphaValue = 1
        } else {
            titleLabel.textColor = .secondaryLabelColor
            closeButton.contentTintColor = .tertiaryLabelColor
            closeButton.alphaValue = isHovered ? 0.7 : 0
        }
        needsDisplay = true  // triggers updateLayer() in correct appearance context
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(index)
    }

    @objc private func closeClicked() {
        onClose?(index)
    }
}
