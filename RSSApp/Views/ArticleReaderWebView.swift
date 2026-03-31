import SwiftUI
import WebKit

struct ArticleReaderWebView: UIViewRepresentable {
    let content: ArticleContent
    let baseURL: URL?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.showsHorizontalScrollIndicator = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(readerHTML, baseURL: baseURL)
    }

    // MARK: - Private

    private var readerHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5">
        <style>
        :root {
            --text: #1c1c1e;
            --bg: #ffffff;
            --secondary: #6e6e73;
            --accent: #007aff;
            --code-bg: #f2f2f7;
            --border: #d1d1d6;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --text: #f2f2f7;
                --bg: #1c1c1e;
                --secondary: #8e8e93;
                --code-bg: #2c2c2e;
                --border: #3a3a3c;
            }
        }
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, 'SF Pro Text', Georgia, serif;
            font-size: 18px;
            line-height: 1.65;
            max-width: 680px;
            margin: 0 auto;
            padding: 20px 16px 60px;
            color: var(--text);
            background: var(--bg);
            -webkit-text-size-adjust: 100%;
            word-break: break-word;
        }
        h1, h2, h3, h4, h5, h6 {
            font-family: -apple-system, 'SF Pro Display', sans-serif;
            font-weight: 600;
            line-height: 1.3;
            margin-top: 1.5em;
        }
        h1 { font-size: 1.5em; }
        h2 { font-size: 1.3em; }
        h3 { font-size: 1.1em; }
        p { margin: 0 0 1em; }
        img, video, iframe {
            max-width: 100%;
            height: auto;
            border-radius: 8px;
            display: block;
            margin: 1em auto;
        }
        a { color: var(--accent); text-decoration: none; }
        a:hover { text-decoration: underline; }
        pre {
            background: var(--code-bg);
            border-radius: 8px;
            padding: 12px;
            overflow-x: auto;
            font-size: 14px;
        }
        code {
            font-family: 'SF Mono', Menlo, Consolas, monospace;
            font-size: 0.9em;
            background: var(--code-bg);
            padding: 2px 5px;
            border-radius: 4px;
        }
        pre code { background: none; padding: 0; }
        blockquote {
            margin: 1em 0;
            padding-left: 16px;
            border-left: 3px solid var(--border);
            color: var(--secondary);
        }
        figure { margin: 1em 0; }
        figcaption {
            font-size: 0.85em;
            color: var(--secondary);
            text-align: center;
            margin-top: 4px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.9em;
            margin: 1em 0;
        }
        th, td {
            border: 1px solid var(--border);
            padding: 8px 12px;
            text-align: left;
        }
        th { background: var(--code-bg); font-weight: 600; }
        </style>
        </head>
        <body>
        \(content.htmlContent)
        </body>
        </html>
        """
    }
}
