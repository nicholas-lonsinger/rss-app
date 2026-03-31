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
    /// Raw RSS description HTML used as fallback when Readability extraction fails.
    let fallbackHTML: String

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "ArticleReaderWebView"
    )

    func makeCoordinator() -> Coordinator {
        Coordinator(extractionState: extractionState, fallbackHTML: fallbackHTML)
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
        private let fallbackHTML: String

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

        /// Fallback extraction that targets common article selectors, then document body.
        private static let domFallbackScript = """
        (function() {
            var selectors = [
                'article', '.entry-content', '.post-content', '.article-content',
                '.article-body', '[role="article"]', 'main', '#content'
            ];
            for (var i = 0; i < selectors.length; i++) {
                var el = document.querySelector(selectors[i]);
                if (el && el.innerText && el.innerText.trim().length > 200) {
                    return JSON.stringify({
                        title: document.title || '',
                        byline: '',
                        content: el.innerHTML,
                        textContent: el.innerText.trim()
                    });
                }
            }
            var body = document.body;
            if (body && body.innerText && body.innerText.trim().length > 200) {
                return JSON.stringify({
                    title: document.title || '',
                    byline: '',
                    content: body.innerHTML,
                    textContent: body.innerText.trim()
                });
            }
            return null;
        })();
        """

        init(extractionState: ReaderExtractionState, fallbackHTML: String) {
            self.extractionState = extractionState
            self.fallbackHTML = fallbackHTML
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Self.logger.debug("Page finished loading, running Readability extraction")
            Task { @MainActor in
                if let content = await self.attemptExtraction(on: webView) {
                    self.extractionState.content = content
                    return
                }

                // Some sites load content dynamically after the initial page load.
                // Retry once after a short delay before falling back.
                Self.logger.debug("First extraction attempt returned nil, retrying after delay")
                try? await Task.sleep(for: .seconds(2))
                if let content = await self.attemptExtraction(on: webView) {
                    self.extractionState.content = content
                    return
                }

                // Readability failed — try targeting common article CSS selectors,
                // then fall back to document.body.innerText for full page content.
                Self.logger.debug("Readability failed, attempting DOM selector fallback")
                if let content = await self.attemptDOMFallback(on: webView) {
                    self.extractionState.content = content
                    return
                }

                Self.logger.warning("All extraction strategies failed, using RSS fallback")
                self.applyFallback()
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            Self.logger.warning("Navigation failed: \(error, privacy: .public)")
            applyFallback()
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            Self.logger.warning("Provisional navigation failed: \(error, privacy: .public)")
            applyFallback()
        }

        /// Attempts Readability extraction, returning `nil` if it fails or produces no result.
        @MainActor
        private func attemptExtraction(on webView: WKWebView) async -> ArticleContent? {
            do {
                let result = try await webView.evaluateJavaScript(Self.extractionScript)

                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8) else {
                    Self.logger.debug("Readability returned nil or non-string result")
                    return nil
                }

                let decoded = try JSONDecoder().decode(ReadabilityResult.self, from: data)
                let content = ArticleContent(
                    title: decoded.title,
                    byline: decoded.byline.isEmpty ? nil : decoded.byline,
                    htmlContent: decoded.content,
                    textContent: decoded.textContent
                )
                Self.logger.notice(
                    "Pre-extraction complete (\(content.textContent.count, privacy: .public) chars)"
                )
                return content
            } catch {
                Self.logger.debug("Extraction attempt failed: \(error, privacy: .public)")
                return nil
            }
        }

        /// Extracts content using common article CSS selectors or document body.
        @MainActor
        private func attemptDOMFallback(on webView: WKWebView) async -> ArticleContent? {
            do {
                let result = try await webView.evaluateJavaScript(Self.domFallbackScript)

                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8) else {
                    Self.logger.debug("DOM fallback returned nil")
                    return nil
                }

                let decoded = try JSONDecoder().decode(ReadabilityResult.self, from: data)
                let content = ArticleContent(
                    title: decoded.title,
                    byline: decoded.byline.isEmpty ? nil : decoded.byline,
                    htmlContent: decoded.content,
                    textContent: decoded.textContent
                )
                Self.logger.notice(
                    "DOM fallback extraction complete (\(content.textContent.count, privacy: .public) chars)"
                )
                return content
            } catch {
                Self.logger.debug("DOM fallback failed: \(error, privacy: .public)")
                return nil
            }
        }

        /// Falls back to the RSS article description when all extraction strategies fail.
        private func applyFallback() {
            let fallbackText = HTMLUtilities.stripHTML(fallbackHTML)
            extractionState.content = ArticleContent(
                title: "",
                byline: nil,
                htmlContent: fallbackHTML,
                textContent: fallbackText
            )
            Self.logger.notice(
                "Applied RSS fallback (\(fallbackText.count, privacy: .public) chars)"
            )
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
