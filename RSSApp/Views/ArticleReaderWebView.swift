import os
import SwiftUI
import WebKit

/// Shared state between the reader WebView and the summary sheet.
/// The coordinator writes extracted content here; the parent view reads it.
@MainActor
@Observable
final class ReaderExtractionState {
    var content: ArticleContent?
}

struct ArticleReaderWebView: UIViewRepresentable {
    let url: URL
    let extractionState: ReaderExtractionState

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "ArticleReaderWebView"
    )

    func makeCoordinator() -> Coordinator {
        Coordinator(extractionState: extractionState)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all

        // Inject Readability.js so it's available when the page finishes loading.
        if let scriptURL = Bundle.main.url(forResource: "readability", withExtension: "js"),
           let readabilityJS = try? String(contentsOf: scriptURL, encoding: .utf8) {
            let userScript = WKUserScript(
                source: readabilityJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(userScript)
        } else {
            Self.logger.fault("readability.js not found in app bundle")
            assertionFailure("readability.js not found in app bundle")
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // URL is constant for the lifetime of this view — no reload needed.
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        private static let logger = Logger(
            subsystem: "com.nicholas-lonsinger.rss-app",
            category: "ArticleReaderWebView.Coordinator"
        )

        private let extractionState: ReaderExtractionState

        private static let extractionScript = """
        (function() {
            try {
                var article = new Readability(document.cloneNode(true)).parse();
                if (!article) return null;
                return JSON.stringify({
                    title: article.title || '',
                    byline: article.byline || '',
                    content: article.content || '',
                    textContent: article.textContent || ''
                });
            } catch(e) {
                return null;
            }
        })();
        """

        init(extractionState: ReaderExtractionState) {
            self.extractionState = extractionState
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Self.logger.debug("Page finished loading, running Readability extraction")
            Task { @MainActor in
                await self.runExtraction(on: webView)
            }
        }

        @MainActor
        private func runExtraction(on webView: WKWebView) async {
            do {
                let result = try await webView.evaluateJavaScript(Self.extractionScript)

                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8) else {
                    Self.logger.warning("Readability returned nil or non-string result")
                    return
                }

                let decoded = try JSONDecoder().decode(ReadabilityResult.self, from: data)
                let content = ArticleContent(
                    title: decoded.title,
                    byline: decoded.byline.isEmpty ? nil : decoded.byline,
                    htmlContent: decoded.content,
                    textContent: decoded.textContent
                )
                extractionState.content = content
                Self.logger.notice(
                    "Pre-extraction complete (\(content.textContent.count, privacy: .public) chars)"
                )
            } catch {
                Self.logger.warning("Pre-extraction failed: \(error, privacy: .public)")
            }
        }
    }
}

// MARK: - Decodable result

private struct ReadabilityResult: Decodable {
    let title: String
    let byline: String
    let content: String
    let textContent: String
}
