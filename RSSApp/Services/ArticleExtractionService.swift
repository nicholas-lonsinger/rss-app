import Foundation
import os
import UIKit
import WebKit

@MainActor
protocol ArticleExtracting {
    func extract(from url: URL, fallbackHTML: String) async throws -> ArticleContent
}

enum ArticleExtractionError: Error, Sendable {
    case serializerNotFound
    case navigationFailed(Error)
    case javascriptFailed
}

@MainActor
final class ArticleExtractionService: ArticleExtracting {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "ArticleExtractionService"
    )

    private let contentExtractor: any ContentExtracting

    init(contentExtractor: (any ContentExtracting)? = nil) {
        self.contentExtractor = contentExtractor ?? ContentExtractor()
    }

    func extract(from url: URL, fallbackHTML: String) async throws -> ArticleContent {
        Self.logger.debug("extract() called for \(url.absoluteString, privacy: .public)")

        guard let scriptURL = Bundle.main.url(forResource: "domSerializer", withExtension: "js"),
              let serializerJS = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            Self.logger.fault("domSerializer.js not found in app bundle")
            assertionFailure("domSerializer.js not found in app bundle")
            throw ArticleExtractionError.serializerNotFound
        }

        do {
            if let content = try await loadAndExtract(url: url, serializerJS: serializerJS) {
                Self.logger.notice("Native extraction succeeded for \(url.absoluteString, privacy: .public)")
                return content
            }
        } catch {
            Self.logger.warning(
                "Extraction failed for \(url.absoluteString, privacy: .public): \(error, privacy: .public) — using RSS fallback"
            )
        }

        // Fall back to RSS articleDescription
        let fallbackText = HTMLUtilities.stripHTML(fallbackHTML)
        return ArticleContent(
            title: "",
            byline: nil,
            htmlContent: fallbackHTML,
            textContent: fallbackText
        )
    }

    // MARK: - Private

    private func loadAndExtract(url: URL, serializerJS: String) async throws -> ArticleContent? {
        try await withCheckedThrowingContinuation { continuation in
            let config = WKWebViewConfiguration()
            config.mediaTypesRequiringUserActionForPlayback = .all

            let userScript = WKUserScript(
                source: serializerJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(userScript)

            let coordinator = ExtractionCoordinator(
                contentExtractor: contentExtractor,
                continuation: continuation
            )

            // RATIONALE: WKWebView must be in the window hierarchy to load pages and
            // fire navigation delegate callbacks reliably. A 1×1 off-screen frame keeps
            // it invisible while satisfying this requirement.
            let webView = WKWebView(frame: CGRect(x: -1, y: -1, width: 1, height: 1), configuration: config)
            webView.navigationDelegate = coordinator
            coordinator.webView = webView

            let keyWindow = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
            keyWindow?.addSubview(webView)

            // 30-second timeout ensures the continuation is always resumed
            // even when the server is unreachable or extremely slow.
            webView.load(URLRequest(url: url, timeoutInterval: 30))
        }
    }
}

// MARK: - Coordinator

/// Bridges WKNavigationDelegate callbacks into the async continuation.
/// Marked @unchecked Sendable because it is only ever accessed on MainActor
/// and its lifecycle is bounded by the single extraction call.
private final class ExtractionCoordinator: NSObject, WKNavigationDelegate, @unchecked Sendable {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "ExtractionCoordinator"
    )

    private let contentExtractor: any ContentExtracting
    private var continuation: CheckedContinuation<ArticleContent?, Error>?
    /// Strong reference keeps the WKWebView alive until extraction completes.
    var webView: WKWebView?
    // RATIONALE: WKWebView.navigationDelegate is weak. This self-reference prevents
    // the coordinator from being deallocated before navigation completes. It is
    // released in cleanup() once the continuation has been resumed.
    private var selfRetain: ExtractionCoordinator?

    init(
        contentExtractor: any ContentExtracting,
        continuation: CheckedContinuation<ArticleContent?, Error>
    ) {
        self.contentExtractor = contentExtractor
        self.continuation = continuation
        super.init()
        selfRetain = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("serializeDOM()") { [weak self] result, error in
            guard let self else { return }
            self.cleanup()

            if let error {
                Self.logger.warning("serializeDOM() error: \(error, privacy: .public)")
                self.continuation?.resume(returning: nil)
                self.continuation = nil
                return
            }

            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8) else {
                Self.logger.debug("serializeDOM() returned nil or non-string result")
                self.continuation?.resume(returning: nil)
                self.continuation = nil
                return
            }

            do {
                let dom = try JSONDecoder().decode(SerializedDOM.self, from: data)
                let content = self.contentExtractor.extract(from: dom)
                self.continuation?.resume(returning: content)
            } catch {
                Self.logger.debug("DOM JSON decoding failed: \(error, privacy: .public)")
                self.continuation?.resume(returning: nil)
            }
            self.continuation = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        cleanup()
        Self.logger.warning("Navigation failed: \(error, privacy: .public)")
        continuation?.resume(throwing: ArticleExtractionError.navigationFailed(error))
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        cleanup()
        Self.logger.warning("Provisional navigation failed: \(error, privacy: .public)")
        continuation?.resume(throwing: ArticleExtractionError.navigationFailed(error))
        continuation = nil
    }

    private func cleanup() {
        webView?.removeFromSuperview()
        webView = nil
        selfRetain = nil  // break self-retain cycle; coordinator deallocates after this returns
    }
}
