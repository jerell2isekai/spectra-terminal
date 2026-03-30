import Foundation

enum MarkdownPreviewSupport {
    static func html(for markdown: String) -> String {
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

    private static func loadBundledJS(_ name: String) -> String {
        guard let url = Bundle.spectraResources.url(forResource: name, withExtension: "js", subdirectory: "js"),
              let data = try? Data(contentsOf: url),
              let str = String(data: data, encoding: .utf8) else {
            return "/* \(name).js not found in bundle */"
        }
        return str
    }
}
