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

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}
