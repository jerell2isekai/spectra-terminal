import AppKit

/// Manages the Agent Supervisor tab content.
///
/// Phase 1: placeholder view with status message.
/// Phase 2+: full supervisor UI with agent list, conversation, and input.
class SupervisorController: TabContent {
    let contentView: NSView
    var tabTitle: String { "Agents" }
    var tabIcon: NSImage? {
        NSImage(systemSymbolName: "brain.head.profile",
                accessibilityDescription: "Agents Supervisor")
    }
    var tabType: TabType { .supervisor }

    init() {
        let placeholder = SupervisorPlaceholderView()
        self.contentView = placeholder
    }

    func detach() {
        contentView.removeFromSuperview()
    }

    func focus() {
        contentView.window?.makeFirstResponder(contentView)
    }
}

// MARK: - Placeholder View (Phase 1)

/// A simple centered label shown until the full supervisor UI is built.
private class SupervisorPlaceholderView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        let icon = NSImageView()
        if let img = NSImage(systemSymbolName: "brain.head.profile",
                             accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .ultraLight)
            icon.image = img.withSymbolConfiguration(config)
        }
        icon.contentTintColor = .tertiaryLabelColor

        let title = NSTextField(labelWithString: "Agents Supervisor")
        title.font = .systemFont(ofSize: 18, weight: .medium)
        title.textColor = .secondaryLabelColor

        let subtitle = NSTextField(labelWithString: "Coming soon — multi-agent orchestration")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [icon, title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Suppress system beep for unhandled keys in placeholder view.
        // Phase 2 will add proper key handling.
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}
