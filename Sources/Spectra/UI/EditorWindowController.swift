import AppKit

/// A lightweight tab for previewing file content or git diffs.
/// Uses the same tabbingIdentifier as MainWindowController so it appears
/// as a tab alongside terminal tabs.
class EditorWindowController: NSWindowController, NSWindowDelegate {

    enum Content {
        case filePreview(url: URL)
        case diff(filePath: String, repoURL: URL)
    }

    private let textView: NSTextView
    private let scrollView: NSScrollView
    private let content: Content
    var onClose: (() -> Void)?

    private static let tabbingID = "com.spectra.terminal"

    init(content: Content) {
        self.content = content

        // Text view setup
        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        // Line number gutter via ruler view
        scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 300, height: 200)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.tabbingID

        super.init(window: window)
        window.delegate = self

        // Set scroll view as content
        window.contentView = scrollView

        loadContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func loadContent() {
        switch content {
        case .filePreview(let url):
            loadFilePreview(url: url)
        case .diff(let filePath, let repoURL):
            loadDiff(filePath: filePath, repoURL: repoURL)
        }
    }

    // MARK: - File Preview

    private func loadFilePreview(url: URL) {
        window?.title = url.lastPathComponent

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let content: String
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                content = text
            } else if let data = try? Data(contentsOf: url) {
                content = "Binary file (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"
            } else {
                content = "Unable to read file"
            }

            DispatchQueue.main.async {
                guard let self else { return }
                let attributed = self.attributedFileContent(content, url: url)
                self.textView.textStorage?.setAttributedString(attributed)
                self.textView.scrollToBeginningOfDocument(nil)
            }
        }
    }

    private func attributedFileContent(_ text: String, url: URL) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let textColor = NSColor.labelColor

        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")

        for (i, line) in lines.enumerated() {
            // Line number prefix
            let lineNum = String(format: "%4d  ", i + 1)
            let numAttr = NSAttributedString(string: lineNum, attributes: [
                .font: font,
                .foregroundColor: NSColor.tertiaryLabelColor,
            ])
            result.append(numAttr)

            // Line content
            let lineAttr = NSAttributedString(string: line, attributes: [
                .font: font,
                .foregroundColor: textColor,
            ])
            result.append(lineAttr)

            if i < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        return result
    }

    // MARK: - Diff View

    private func loadDiff(filePath: String, repoURL: URL) {
        window?.title = "Diff: \(filePath)"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let diffOutput = GitStatusProvider.fetchFileDiff(filePath: filePath, repoURL: repoURL)

            DispatchQueue.main.async {
                guard let self else { return }
                if diffOutput.isEmpty {
                    let attr = NSAttributedString(string: "No changes", attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ])
                    self.textView.textStorage?.setAttributedString(attr)
                } else {
                    let attributed = self.attributedDiffContent(diffOutput)
                    self.textView.textStorage?.setAttributedString(attributed)
                }
                self.textView.scrollToBeginningOfDocument(nil)
            }
        }
    }

    private func attributedDiffContent(_ diff: String) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let result = NSMutableAttributedString()
        let lines = diff.components(separatedBy: "\n")

        for (i, line) in lines.enumerated() {
            let color: NSColor
            let bgColor: NSColor

            if line.hasPrefix("+++") || line.hasPrefix("---") {
                color = .secondaryLabelColor
                bgColor = .clear
            } else if line.hasPrefix("@@") {
                color = NSColor.systemCyan
                bgColor = NSColor.systemCyan.withAlphaComponent(0.1)
            } else if line.hasPrefix("+") {
                color = NSColor.systemGreen
                bgColor = NSColor.systemGreen.withAlphaComponent(0.08)
            } else if line.hasPrefix("-") {
                color = NSColor.systemRed
                bgColor = NSColor.systemRed.withAlphaComponent(0.08)
            } else {
                color = .labelColor
                bgColor = .clear
            }

            let lineAttr = NSAttributedString(string: line, attributes: [
                .font: font,
                .foregroundColor: color,
                .backgroundColor: bgColor,
            ])
            result.append(lineAttr)

            if i < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        return result
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
