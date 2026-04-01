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
    /// Raw RSS description HTML used as fallback when all extraction strategies fail.
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

        // Inject domSerializer.js at document end — fires after the document has loaded
        // but before subresources (images, ads) finish loading. This enables early
        // extraction since article content is usually in the initial HTML.
        do {
            guard let scriptURL = Bundle.main.url(forResource: "domSerializer", withExtension: "js") else {
                throw ArticleExtractionError.serializerNotFound
            }
            let serializerJS = try String(contentsOf: scriptURL, encoding: .utf8)
            let userScript = WKUserScript(
                source: serializerJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(userScript)
        } catch {
            Self.logger.fault("domSerializer.js not available: \(error, privacy: .public)")
            assertionFailure("domSerializer.js not available: \(error)")
        }

        config.userContentController.add(context.coordinator, name: DOMSerializerConstants.messageHandlerName)

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

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private static let logger = Logger(
            subsystem: "com.nicholas-lonsinger.rss-app",
            category: "ArticleReaderWebView.Coordinator"
        )

        private let extractionState: ReaderExtractionState
        private let fallbackHTML: String
        private let contentExtractor: any ContentExtracting

        /// Tracks whether early extraction already succeeded, so `didFinish` can skip redundant work.
        private var earlyExtractionSucceeded = false

        init(
            extractionState: ReaderExtractionState,
            fallbackHTML: String,
            contentExtractor: (any ContentExtracting)? = nil
        ) {
            self.extractionState = extractionState
            self.fallbackHTML = fallbackHTML
            self.contentExtractor = contentExtractor ?? ContentExtractor()
        }

        // MARK: - WKScriptMessageHandler (early extraction)

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == DOMSerializerConstants.messageHandlerName else { return }
            guard let jsonString = message.body as? String else {
                Self.logger.warning("Message handler received non-string body: \(type(of: message.body))")
                return
            }

            Self.logger.debug("Received early DOM serialization via message handler")

            if let content = extractFromJSON(jsonString) {
                extractionState.content = content
                earlyExtractionSucceeded = true
                Self.logger.notice(
                    "Early extraction succeeded (\(content.textContent.count, privacy: .public) chars)"
                )
            } else {
                Self.logger.debug("Early extraction produced no content — will retry on didFinish")
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !earlyExtractionSucceeded else {
                Self.logger.debug("Skipping didFinish extraction — early extraction already succeeded")
                return
            }

            Self.logger.debug("Page finished loading, running DOM serialization")
            Task { @MainActor in
                if let content = await self.attemptExtraction(on: webView) {
                    self.extractionState.content = content
                    return
                }

                // Some sites load content dynamically after the initial page load.
                // Retry once after a short delay before falling back.
                Self.logger.debug("First didFinish extraction returned nil, retrying after delay")
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    Self.logger.debug("Retry cancelled")
                    return
                }
                if let content = await self.attemptExtraction(on: webView) {
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

        // MARK: - Extraction

        /// Runs the DOM serializer via evaluateJavaScript and processes the result in Swift.
        @MainActor
        private func attemptExtraction(on webView: WKWebView) async -> ArticleContent? {
            do {
                let result = try await webView.evaluateJavaScript(DOMSerializerConstants.serializerCall)

                guard let jsonString = result as? String else {
                    Self.logger.warning("serializeDOM() returned nil or non-string result")
                    return nil
                }

                return extractFromJSON(jsonString)
            } catch {
                Self.logger.warning("serializeDOM() failed: \(error, privacy: .public)")
                return nil
            }
        }

        /// Decodes serialized DOM JSON and runs the Swift content extractor.
        private func extractFromJSON(_ jsonString: String) -> ArticleContent? {
            // RATIONALE: Swift String.data(using: .utf8) never returns nil for valid String values.
            // This guard satisfies the compiler; the else branch is unreachable.
            guard let data = jsonString.data(using: .utf8) else { return nil }

            do {
                let dom = try JSONDecoder().decode(SerializedDOM.self, from: data)
                return contentExtractor.extract(from: dom)
            } catch {
                Self.logger.warning("DOM JSON decoding failed: \(error, privacy: .public)")
                return nil
            }
        }

        /// Falls back to the RSS article description when all extraction strategies fail.
        private func applyFallback() {
            let content = ArticleContent.rssFallback(html: fallbackHTML)
            extractionState.content = content
            Self.logger.notice(
                "Applied RSS fallback (\(content.textContent.count, privacy: .public) chars)"
            )
        }
    }
}
