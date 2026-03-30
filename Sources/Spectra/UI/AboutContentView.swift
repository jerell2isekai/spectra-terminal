import AppKit

/// About panel content designed to be embedded inside an OverlayPanel.
class AboutContentView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 32, bottom: 24, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // App icon
        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            iconView.image = icon
        } else {
            iconView.image = NSApp.applicationIconImage
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 96).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 96).isActive = true
        stack.addArrangedSubview(iconView)

        // App name
        let nameLabel = NSTextField(labelWithString: "Spectra")
        nameLabel.font = .systemFont(ofSize: 22, weight: .bold)
        nameLabel.textColor = .labelColor
        nameLabel.alignment = .center
        stack.addArrangedSubview(nameLabel)

        // Version
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let versionText = build.isEmpty ? "Version \(version)" : "Version \(version) (\(build))"
        let versionLabel = NSTextField(labelWithString: versionText)
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        stack.addArrangedSubview(versionLabel)

        // Description
        stack.setCustomSpacing(16, after: versionLabel)
        let descLabel = NSTextField(labelWithString: "A GPU-accelerated terminal emulator\npowered by libghostty")
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .tertiaryLabelColor
        descLabel.alignment = .center
        descLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(descLabel)

        // Links
        stack.setCustomSpacing(16, after: descLabel)
        let linksStack = NSStackView()
        linksStack.orientation = .horizontal
        linksStack.spacing = 16

        let websiteButton = makeLink(title: "Website", url: "https://spectra.librefox.app")
        let githubButton = makeLink(title: "GitHub", url: "https://github.com/jerell2isekai/spectra")
        let releasesButton = makeLink(title: "Releases", url: "https://github.com/jerell2isekai/spectra/releases")

        linksStack.addArrangedSubview(websiteButton)
        linksStack.addArrangedSubview(githubButton)
        linksStack.addArrangedSubview(releasesButton)
        stack.addArrangedSubview(linksStack)

        // Ghostty acknowledgment
        stack.setCustomSpacing(12, after: linksStack)
        let ackLabel = NSTextField(labelWithString: "Built on libghostty by the Ghostty team")
        ackLabel.font = .systemFont(ofSize: 11)
        ackLabel.textColor = .quaternaryLabelColor
        ackLabel.alignment = .center
        stack.addArrangedSubview(ackLabel)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func makeLink(title: String, url: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(openLink(_:)))
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.font = .systemFont(ofSize: 12)
        button.contentTintColor = .controlAccentColor
        button.toolTip = url
        button.identifier = NSUserInterfaceItemIdentifier(url)
        return button
    }

    @objc private func openLink(_ sender: NSButton) {
        guard let urlString = sender.identifier?.rawValue,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
