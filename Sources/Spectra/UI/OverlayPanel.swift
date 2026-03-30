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
    private var panelHeightConstraint: NSLayoutConstraint?
    private var panelCenterYConstraint: NSLayoutConstraint?

    private var eventMonitor: Any?
    private let panelSize: Size

    // Resize state (large mode only)
    private enum ResizeEdge { case none, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }
    private var activeResize: ResizeEdge = .none
    private var resizeTrackingArea: NSTrackingArea?
    private static let resizeMargin: CGFloat = 8
    private static let cornerMargin: CGFloat = 20
    private static let minPanelWidth: CGFloat = 400
    private static let minPanelHeight: CGFloat = 300

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
            // Explicit constraints — updated in show() with saved/default values, resizable via drag
            let w = panelView.widthAnchor.constraint(equalToConstant: 100)
            let h = panelView.heightAnchor.constraint(equalToConstant: 100)
            panelWidthConstraint = w
            panelHeightConstraint = h
            NSLayoutConstraint.activate([w, h])
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

        // Set large panel size from UserDefaults or default proportions
        if panelSize == .large {
            let parentW = parentView.bounds.width
            let parentH = parentView.bounds.height
            let savedW = CGFloat(UserDefaults.standard.double(forKey: "overlayPanelWidth"))
            let savedH = CGFloat(UserDefaults.standard.double(forKey: "overlayPanelHeight"))
            let maxW = parentW - 40
            let maxH = parentH - 40
            panelWidthConstraint?.constant = savedW >= Self.minPanelWidth
                ? Swift.min(savedW, maxW) : parentW * 0.85
            panelHeightConstraint?.constant = savedH >= Self.minPanelHeight
                ? Swift.min(savedH, maxH) : parentH * 0.9
        }

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
        if panelSize == .large { installResizeTracking() }
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

    // MARK: - Resize (large mode)

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Intercept mouse events near panel edges for resize — prevents subviews from absorbing them
        if panelSize == .large && detectEdge(at: point) != .none {
            return self
        }
        return super.hitTest(point)
    }

    private func installResizeTracking() {
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        resizeTrackingArea = area
    }

    private func detectEdge(at point: NSPoint) -> ResizeEdge {
        guard panelSize == .large else { return .none }
        let f = panelView.frame
        let m = Self.resizeMargin
        let cm = Self.cornerMargin  // larger zone for corners

        // Distance from each edge (negative = inside, positive = outside)
        let dL = point.x - f.minX   // positive when right of left edge
        let dR = f.maxX - point.x   // positive when left of right edge
        let dB = point.y - f.minY   // positive when above bottom edge
        let dT = f.maxY - point.y   // positive when below top edge

        let nearL = abs(dL) < m
        let nearR = abs(dR) < m
        let nearB = abs(dB) < m
        let nearT = abs(dT) < m

        // Corner zones: larger hit area (cornerMargin × cornerMargin from each corner)
        let inCornerL = dL > -m && dL < cm
        let inCornerR = dR > -m && dR < cm
        let inCornerB = dB > -m && dB < cm
        let inCornerT = dT > -m && dT < cm

        // Corners first (larger hit zone)
        if inCornerT && inCornerL { return .topLeft }
        if inCornerT && inCornerR { return .topRight }
        if inCornerB && inCornerL { return .bottomLeft }
        if inCornerB && inCornerR { return .bottomRight }

        // Edges (within resizeMargin of each edge, and within panel Y/X range)
        let inPanelX = point.x > f.minX + cm && point.x < f.maxX - cm
        let inPanelY = point.y > f.minY + cm && point.y < f.maxY - cm
        if nearL && inPanelY { return .left }
        if nearR && inPanelY { return .right }
        if nearT && inPanelX { return .top }
        if nearB && inPanelX { return .bottom }
        return .none
    }

    private func cursor(for edge: ResizeEdge) -> NSCursor {
        switch edge {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case .topLeft, .bottomRight: return Self.resizeNWSE
        case .topRight, .bottomLeft: return Self.resizeNESW
        case .none: return .arrow
        }
    }

    // Diagonal resize cursors loaded from the HIServices system cursor directory.
    // Same approach used by SDL and Skim — stable since macOS 10.6.
    private static let resizeNWSE: NSCursor = loadSystemCursor("resizenorthwestsoutheast") ?? .crosshair
    private static let resizeNESW: NSCursor = loadSystemCursor("resizenortheastsouthwest") ?? .crosshair

    private static func loadSystemCursor(_ name: String) -> NSCursor? {
        let base = "/System/Library/Frameworks/ApplicationServices.framework"
            + "/Versions/A/Frameworks/HIServices.framework"
            + "/Versions/A/Resources/cursors"
        let dir = "\(base)/\(name)"
        guard let image = NSImage(contentsOfFile: "\(dir)/cursor.pdf") else { return nil }
        var hotSpot = NSPoint(x: 8, y: 8)
        if let info = NSDictionary(contentsOfFile: "\(dir)/info.plist") {
            hotSpot = NSPoint(x: info["hotx"] as? Double ?? 8, y: info["hoty"] as? Double ?? 8)
        }
        return NSCursor(image: image, hotSpot: hotSpot)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard panelSize == .large else { return }
        let f = panelView.frame
        let m = Self.resizeMargin
        let cm = Self.cornerMargin

        // Corners (larger hit zones)
        let nwse = Self.resizeNWSE
        let nesw = Self.resizeNESW
        addCursorRect(NSRect(x: f.minX - m, y: f.maxY - cm, width: cm + m, height: cm + m), cursor: nwse)  // topLeft
        addCursorRect(NSRect(x: f.maxX - cm, y: f.maxY - cm, width: cm + m, height: cm + m), cursor: nesw)  // topRight
        addCursorRect(NSRect(x: f.minX - m, y: f.minY - m, width: cm + m, height: cm + m), cursor: nesw)    // bottomLeft
        addCursorRect(NSRect(x: f.maxX - cm, y: f.minY - m, width: cm + m, height: cm + m), cursor: nwse)    // bottomRight

        // Edges (between corners)
        addCursorRect(NSRect(x: f.minX - m, y: f.minY + cm, width: m * 2, height: f.height - cm * 2), cursor: .resizeLeftRight)   // left
        addCursorRect(NSRect(x: f.maxX - m, y: f.minY + cm, width: m * 2, height: f.height - cm * 2), cursor: .resizeLeftRight)   // right
        addCursorRect(NSRect(x: f.minX + cm, y: f.maxY - m, width: f.width - cm * 2, height: m * 2), cursor: .resizeUpDown)       // top
        addCursorRect(NSRect(x: f.minX + cm, y: f.minY - m, width: f.width - cm * 2, height: m * 2), cursor: .resizeUpDown)       // bottom
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard panelSize == .large else { super.mouseDown(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        let edge = detectEdge(at: point)
        if edge != .none {
            activeResize = edge
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard panelSize == .large, activeResize != .none,
              let wc = panelWidthConstraint, let hc = panelHeightConstraint else {
            super.mouseDragged(with: event)
            return
        }

        let dx = event.deltaX
        let dy = event.deltaY
        let maxW = bounds.width - 40
        let maxH = bounds.height - 40

        // Since panel is centered, edge drag changes size symmetrically (2x delta)
        var newW = wc.constant
        var newH = hc.constant

        // NSEvent.deltaY: positive = mouse moved down (screen coords)
        switch activeResize {
        case .left:       newW -= dx * 2
        case .right:      newW += dx * 2
        case .top:        newH -= dy * 2  // drag top up (dy<0): height increases
        case .bottom:     newH += dy * 2  // drag bottom down (dy>0): height increases
        case .topLeft:    newW -= dx * 2; newH -= dy * 2
        case .topRight:   newW += dx * 2; newH -= dy * 2
        case .bottomLeft: newW -= dx * 2; newH += dy * 2
        case .bottomRight: newW += dx * 2; newH += dy * 2
        case .none: return
        }

        // Clamp
        newW = Swift.max(Self.minPanelWidth, Swift.min(newW, maxW))
        newH = Swift.max(Self.minPanelHeight, Swift.min(newH, maxH))

        wc.constant = newW
        hc.constant = newH
        window?.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
        if panelSize == .large && activeResize != .none {
            // Persist size
            if let wc = panelWidthConstraint, let hc = panelHeightConstraint {
                UserDefaults.standard.set(Double(wc.constant), forKey: "overlayPanelWidth")
                UserDefaults.standard.set(Double(hc.constant), forKey: "overlayPanelHeight")
            }
            activeResize = .none
            NSCursor.arrow.set()
        } else {
            super.mouseUp(with: event)
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
