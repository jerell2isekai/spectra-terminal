import AppKit
import WebKit

/// Content-type-aware file preview that supports Markdown rendering, JSON formatting,
/// and plain text with line numbers. Designed to be embedded inside an OverlayPanel.
class PreviewContentView: NSView, WKNavigationDelegate {

    enum FileType {
        case markdown
        case json
        case plainText
    }

    private let url: URL
    private let fileType: FileType
    private var rawText: String = ""
    private var isRenderedMode: Bool  // markdown: true=preview, json: true=pretty

    // Views
    private let textScrollView: NSScrollView
    private let textView: NSTextView
    private var webView: WKWebView?
    private let modeControl: NSSegmentedControl

    init(url: URL) {
        self.url = url
        self.fileType = Self.detectFileType(url)

        // Mode control setup
        switch self.fileType {
        case .markdown:
            modeControl = NSSegmentedControl(labels: ["Raw", "Preview"], trackingMode: .selectOne, target: nil, action: nil)
            modeControl.selectedSegment = 1  // default: Preview
            isRenderedMode = true
        case .json:
            modeControl = NSSegmentedControl(labels: ["Compact", "Pretty"], trackingMode: .selectOne, target: nil, action: nil)
            modeControl.selectedSegment = 1  // default: Pretty
            isRenderedMode = true
        case .plainText:
            modeControl = NSSegmentedControl()
            modeControl.isHidden = true
            isRenderedMode = false
        }

        // Text view
        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.textColor = .labelColor
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.textContainerInset = NSSize(width: 12, height: 12)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        self.textView = tv

        let sv = NSScrollView()
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        self.textScrollView = sv

        super.init(frame: .zero)

        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))

        textScrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textScrollView)
        NSLayoutConstraint.activate([
            textScrollView.topAnchor.constraint(equalTo: topAnchor),
            textScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        loadContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The mode toggle control for the overlay header. Nil for plain text files.
    var headerToolbar: NSView? {
        fileType == .plainText ? nil : modeControl
    }

    // MARK: - File Type Detection

    private static func detectFileType(_ url: URL) -> FileType {
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd":
            return .markdown
        case "json", "geojson":
            return .json
        default:
            return .plainText
        }
    }

    // MARK: - Content Loading

    private func loadContent() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let text: String
            if let t = try? String(contentsOf: self.url, encoding: .utf8) {
                text = t
            } else if let data = try? Data(contentsOf: self.url) {
                text = "Binary file (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"
            } else {
                text = "Unable to read file"
            }

            DispatchQueue.main.async {
                guard self.superview != nil else { return }
                self.rawText = text
                self.applyCurrentMode()
            }
        }
    }

    // MARK: - Mode Switching

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        switch fileType {
        case .markdown:
            isRenderedMode = sender.selectedSegment == 1  // 0=Raw, 1=Preview
        case .json:
            isRenderedMode = sender.selectedSegment == 1  // 0=Compact, 1=Pretty
        case .plainText:
            return
        }
        applyCurrentMode()
    }

    private func applyCurrentMode() {
        switch fileType {
        case .markdown:
            if isRenderedMode {
                showMarkdownPreview()
            } else {
                showRawText()
            }
        case .json:
            showJSON(pretty: isRenderedMode)
        case .plainText:
            showPlainText()
        }
    }

    // MARK: - Text View Display

    private func showPlainText() {
        showTextContent(rawText)
    }

    private func showRawText() {
        showTextContent(rawText)
    }

    private func showTextContent(_ text: String) {
        hideWebView()
        textScrollView.isHidden = false
        let attributed = Self.attributedFileContent(text)
        textView.textStorage?.setAttributedString(attributed)
        textView.scrollToBeginningOfDocument(nil)
    }

    // MARK: - Markdown Preview

    private func showMarkdownPreview() {
        textScrollView.isHidden = true

        let wv = ensureWebView()
        wv.isHidden = false

        let html = Self.markdownHTML(rawText)
        wv.loadHTMLString(html, baseURL: nil)
    }

    private func ensureWebView() -> WKWebView {
        if let wv = webView { return wv }

        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.setValue(false, forKey: "drawsBackground")
        addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: topAnchor),
            wv.bottomAnchor.constraint(equalTo: bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        webView = wv
        return wv
    }

    private func hideWebView() {
        webView?.isHidden = true
    }

    // MARK: - JSON Formatting

    private func showJSON(pretty: Bool) {
        hideWebView()
        textScrollView.isHidden = false

        let displayText: String
        if let data = rawText.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
            let options: JSONSerialization.WritingOptions = pretty
                ? [.prettyPrinted, .sortedKeys]
                : [.sortedKeys]
            if let formatted = try? JSONSerialization.data(withJSONObject: obj, options: options),
               let str = String(data: formatted, encoding: .utf8) {
                displayText = str
            } else {
                displayText = rawText
            }
        } else {
            displayText = rawText  // fallback: show as-is if not valid JSON
        }

        let attributed = Self.attributedFileContent(displayText)
        textView.textStorage?.setAttributedString(attributed)
        textView.scrollToBeginningOfDocument(nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Allow initial HTML string load, block all other navigation
        if navigationAction.navigationType == .other {
            decisionHandler(.allow)
        } else {
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }

    // MARK: - Attributed Text Helpers

    private static func attributedFileContent(_ text: String) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let lineNum = String(format: "%4d  ", i + 1)
            result.append(NSAttributedString(string: lineNum, attributes: [
                .font: font,
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]))
            result.append(NSAttributedString(string: line, attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]))
            if i < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result
    }

    // MARK: - Markdown HTML Template

    // MARK: - Bundled JS Helpers

    private static func loadBundledJS(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "js"),
              let data = try? Data(contentsOf: url),
              let str = String(data: data, encoding: .utf8) else {
            return "/* \(name).js not found in bundle */"
        }
        return str
    }

    /// Build a self-contained HTML page that renders markdown with mermaid support.
    /// All JS libraries (marked, mermaid, DOMPurify) are bundled — no network required.
    /// Content source: local files only (not untrusted network input).
    private static func markdownHTML(_ markdown: String) -> String {
        let encoder = JSONEncoder()
        let jsonData = (try? encoder.encode(markdown)) ?? Data("\"\"".utf8)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "\"\""

        let markedJS = loadBundledJS("marked.min")
        let mermaidJS = loadBundledJS("mermaid.min")
        let purifyJS = loadBundledJS("purify.min")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light dark; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
            padding: 16px 24px;
            margin: 0;
            line-height: 1.6;
            font-size: 14px;
            background: transparent;
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --text: #e0e0e0; --text-secondary: #999;
              --code-bg: rgba(255,255,255,0.06); --code-border: rgba(255,255,255,0.1);
              --border: #333; --link: #58a6ff;
              --blockquote: #888; --table-stripe: rgba(255,255,255,0.03);
            }
          }
          @media (prefers-color-scheme: light) {
            :root {
              --text: #1a1a1a; --text-secondary: #666;
              --code-bg: rgba(0,0,0,0.04); --code-border: rgba(0,0,0,0.08);
              --border: #d0d7de; --link: #0969da;
              --blockquote: #666; --table-stripe: rgba(0,0,0,0.02);
            }
          }
          body { color: var(--text); }
          a { color: var(--link); text-decoration: none; }
          a:hover { text-decoration: underline; }
          code {
            background: var(--code-bg);
            border: 1px solid var(--code-border);
            padding: 1px 5px;
            border-radius: 4px;
            font-family: 'SF Mono', Menlo, monospace;
            font-size: 0.9em;
          }
          pre {
            background: var(--code-bg);
            border: 1px solid var(--code-border);
            padding: 14px;
            border-radius: 8px;
            overflow-x: auto;
            line-height: 1.45;
          }
          pre code { background: none; border: none; padding: 0; font-size: 13px; }
          blockquote {
            border-left: 3px solid var(--border);
            margin: 8px 0;
            padding-left: 16px;
            color: var(--blockquote);
          }
          table { border-collapse: collapse; width: 100%; margin: 12px 0; }
          th, td { border: 1px solid var(--border); padding: 8px 12px; text-align: left; }
          th { font-weight: 600; }
          tr:nth-child(even) { background: var(--table-stripe); }
          img { max-width: 100%; border-radius: 6px; }
          h1, h2 { border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
          h1 { font-size: 1.8em; }
          h2 { font-size: 1.4em; }
          h3 { font-size: 1.2em; }
          hr { border: none; border-top: 1px solid var(--border); margin: 24px 0; }
          .mermaid { text-align: center; margin: 16px 0; }
          .task-list-item { list-style: none; }
          .task-list-item input { margin-right: 6px; }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script>\(markedJS)</script>
        <script>\(mermaidJS)</script>
        <script>\(purifyJS)</script>
        <script>
        (function() {
          var raw = \(jsonString);
          var el = document.getElementById('content');

          // Fallback: if marked didn't load, show raw text
          if (typeof marked === 'undefined') {
            var pre = document.createElement('pre');
            pre.style.whiteSpace = 'pre-wrap';
            pre.style.fontFamily = "'SF Mono', Menlo, monospace";
            pre.style.fontSize = '13px';
            pre.textContent = raw;
            el.appendChild(pre);
            return;
          }

          var isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
          if (typeof mermaid !== 'undefined') {
            mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: isDark ? 'dark' : 'default' });
          }

          marked.use({
            renderer: {
              code: function(token) {
                if (token.lang === 'mermaid' && typeof mermaid !== 'undefined') {
                  return '<div class="mermaid">' + token.text + '</div>';
                }
                return false;
              }
            }
          });

          var parsed = marked.parse(raw);
          // Sanitize HTML through DOMPurify before rendering
          if (typeof DOMPurify !== 'undefined') {
            parsed = DOMPurify.sanitize(parsed, {
              ADD_TAGS: ['div'],
              ADD_ATTR: ['class'],
              CUSTOM_ELEMENT_HANDLING: {
                tagNameCheck: /^div$/,
                attributeNameCheck: /^class$/,
                allowCustomizedBuiltInElements: false
              }
            });
          }
          el.innerHTML = parsed;

          try { if (typeof mermaid !== 'undefined') mermaid.run(); } catch(e) { console.warn('Mermaid:', e); }
        })();
        </script>
        </body>
        </html>
        """
    }
}
