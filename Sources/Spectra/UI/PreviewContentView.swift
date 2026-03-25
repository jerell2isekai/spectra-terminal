import AppKit
import PDFKit
import WebKit

/// Content-type-aware file preview that supports Markdown rendering, JSON formatting,
/// and plain text with line numbers. Designed to be embedded inside an OverlayPanel.
class PreviewContentView: NSView, WKNavigationDelegate {

    enum FileType {
        case markdown
        case html
        case json
        case pdf
        case image
        case plainText
    }

    private let url: URL
    private let fileType: FileType
    private var rawText: String = ""
    private var isRenderedMode: Bool  // markdown: true=preview, json: true=pretty

    // Views
    private let textScrollView: NSScrollView
    private let textView: NSTextView
    private var webView: WKWebView?            // markdown (JS enabled for marked/mermaid)
    private var hardenedWebView: WKWebView?    // HTML preview (JS disabled, sandboxed)
    private let modeControl: NSSegmentedControl
    private static var compiledContentRules: WKContentRuleList?

    init(url: URL) {
        self.url = url
        self.fileType = Self.detectFileType(url)

        // Mode control setup
        switch self.fileType {
        case .markdown, .html:
            modeControl = NSSegmentedControl(labels: ["Raw", "Preview"], trackingMode: .selectOne, target: nil, action: nil)
            modeControl.selectedSegment = 1  // default: Preview
            isRenderedMode = true
        case .json:
            modeControl = NSSegmentedControl(labels: ["Compact", "Pretty"], trackingMode: .selectOne, target: nil, action: nil)
            modeControl.selectedSegment = 1  // default: Pretty
            isRenderedMode = true
        case .pdf, .image, .plainText:
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
        modeControl.isHidden ? nil : modeControl
    }

    // MARK: - File Type Detection

    private static func detectFileType(_ url: URL) -> FileType {
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd":
            return .markdown
        case "html", "htm", "xhtml":
            return .html
        case "json", "geojson":
            return .json
        case "pdf":
            return .pdf
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "ico", "svg", "heic", "heif":
            return .image
        default:
            return .plainText
        }
    }

    // MARK: - Content Loading

    private func loadContent() {
        // PDF and image don't need text loading
        switch fileType {
        case .pdf:
            showPDF()
            return
        case .image:
            showImage()
            return
        default:
            break
        }

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
        case .markdown, .html:
            isRenderedMode = sender.selectedSegment == 1  // 0=Raw, 1=Preview
        case .json:
            isRenderedMode = sender.selectedSegment == 1  // 0=Compact, 1=Pretty
        case .pdf, .image, .plainText:
            return
        }
        applyCurrentMode()
    }

    private func applyCurrentMode() {
        switch fileType {
        case .markdown:
            isRenderedMode ? showMarkdownPreview() : showRawText()
        case .html:
            isRenderedMode ? showHTMLPreview() : showRawText()
        case .json:
            showJSON(pretty: isRenderedMode)
        case .pdf:
            showPDF()
        case .image:
            showImage()
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

    /// WebView for markdown preview (JS enabled for marked.js/mermaid/DOMPurify).
    private func ensureWebView() -> WKWebView {
        if let wv = webView { return wv }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
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

    /// Hardened WebView for HTML file preview — JS disabled, no network, ephemeral storage.
    private func ensureHardenedWebView() -> WKWebView {
        if let wv = hardenedWebView { return wv }

        let config = WKWebViewConfiguration()
        // Layer 1: Disable JavaScript execution in content
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        // Layer 2: Ephemeral storage — no cookies/cache persisted to disk
        config.websiteDataStore = .nonPersistent()
        // Layer 3: Content blocker rules (if pre-compiled)
        if let rules = Self.compiledContentRules {
            config.userContentController.add(rules)
        }

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
        hardenedWebView = wv
        return wv
    }

    /// Pre-compile content blocker rules (call once at app startup or first use).
    static func precompileContentRules() {
        let rules = """
        [
            {"trigger":{"url-filter":".*","resource-type":["script","raw","media","popup"]},
             "action":{"type":"block"}},
            {"trigger":{"url-filter":".*","load-type":["third-party"]},
             "action":{"type":"block"}},
            {"trigger":{"url-filter":".*"},
             "action":{"type":"block-cookies"}}
        ]
        """
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "StaticPreviewBlocker",
            encodedContentRuleList: rules
        ) { ruleList, _ in
            Self.compiledContentRules = ruleList
        }
    }

    private func hideWebView() {
        webView?.isHidden = true
        hardenedWebView?.isHidden = true
    }

    // MARK: - HTML Preview (hardened — static content only)

    private func showHTMLPreview() {
        textScrollView.isHidden = true
        webView?.isHidden = true

        let wv = ensureHardenedWebView()
        wv.isHidden = false

        // Layer 4: Inject CSP meta tag — blocks scripts, network, forms
        let csp = #"<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline' 'self'; img-src 'self' data:; font-src 'self' data:;">"#
        let sanitized: String
        if let range = rawText.range(of: "<head>", options: .caseInsensitive) {
            var html = rawText
            html.insert(contentsOf: "\n\(csp)\n", at: range.upperBound)
            sanitized = html
        } else if let range = rawText.range(of: "<html", options: .caseInsensitive),
                  let close = rawText[range.upperBound...].range(of: ">") {
            var html = rawText
            html.insert(contentsOf: "<head>\(csp)</head>", at: close.upperBound)
            sanitized = html
        } else {
            sanitized = csp + "\n" + rawText
        }

        // Layer 5: baseURL set to file directory for relative CSS/images, but JS is blocked
        wv.loadHTMLString(sanitized, baseURL: url.deletingLastPathComponent())
    }

    // MARK: - PDF Preview

    private var pdfScrollView: NSScrollView?

    private func showPDF() {
        hideWebView()
        textScrollView.isHidden = true

        guard let doc = PDFDocument(url: url) else {
            rawText = "Unable to load PDF"
            showPlainText()
            return
        }

        let pdfView = PDFView()
        pdfView.document = doc
        pdfView.autoScales = true
        pdfView.backgroundColor = .clear
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    // MARK: - Image Preview

    private var imageScrollView: NSScrollView?

    private func showImage() {
        hideWebView()
        textScrollView.isHidden = true

        if let existing = imageScrollView {
            existing.isHidden = false
            return
        }

        guard let image = NSImage(contentsOf: url) else {
            rawText = "Unable to load image"
            showPlainText()
            return
        }

        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let sv = NSScrollView()
        sv.documentView = imageView
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = true
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.translatesAutoresizingMaskIntoConstraints = false

        // Size the image view to its natural size for scrolling
        let imgSize = image.size
        imageView.widthAnchor.constraint(greaterThanOrEqualToConstant: imgSize.width).isActive = true
        imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: imgSize.height).isActive = true
        // Also allow it to fill the scroll view if smaller
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)

        addSubview(sv)
        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: topAnchor),
            sv.bottomAnchor.constraint(equalTo: bottomAnchor),
            sv.leadingAnchor.constraint(equalTo: leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        imageScrollView = sv
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
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        // Layer 6: Per-navigation JS enforcement for hardened web view
        if webView === hardenedWebView {
            preferences.allowsContentJavaScript = false
        }
        // Allow initial HTML string load, open external links in system browser
        if navigationAction.navigationType == .other {
            decisionHandler(.allow, preferences)
        } else {
            if let url = navigationAction.request.url, url.scheme == "https" || url.scheme == "http" {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel, preferences)
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
