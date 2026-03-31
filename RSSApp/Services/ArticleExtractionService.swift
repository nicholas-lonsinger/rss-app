import Foundation
import os
import UIKit
import WebKit

@MainActor
protocol ArticleExtracting {
    func extract(from url: URL, fallbackHTML: String) async throws -> ArticleContent
}

enum ArticleExtractionError: Error, Sendable {
    case readabilityNotFound
    case navigationFailed(Error)
    case javascriptFailed
}

@MainActor
final class ArticleExtractionService: ArticleExtracting {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "ArticleExtractionService"
    )

    // Small extraction script — Readability.js is pre-injected as a WKUserScript.
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

    func extract(from url: URL, fallbackHTML: String) async throws -> ArticleContent {
        Self.logger.debug("extract() called for \(url.absoluteString, privacy: .public)")

        guard let scriptURL = Bundle.main.url(forResource: "readability", withExtension: "js"),
              let readabilityJS = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            Self.logger.fault("readability.js not found in app bundle")
            assertionFailure("readability.js not found in app bundle")
            throw ArticleExtractionError.readabilityNotFound
        }

        do {
            if let content = try await loadAndExtract(url: url, readabilityJS: readabilityJS) {
                Self.logger.notice("Readability extraction succeeded for \(url.absoluteString, privacy: .public)")
                return content
            }
        } catch {
            Self.logger.warning("Extraction failed for \(url.absoluteString, privacy: .public): \(error, privacy: .public) — using RSS fallback")
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

    private func loadAndExtract(url: URL, readabilityJS: String) async throws -> ArticleContent? {
        try await withCheckedThrowingContinuation { continuation in
            let config = WKWebViewConfiguration()
            config.mediaTypesRequiringUserActionForPlayback = .all

            // Inject Readability.js at document-end so it is already defined
            // by the time didFinishNavigation fires and we run the extraction script.
            let userScript = WKUserScript(
                source: readabilityJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(userScript)

            let coordinator = ExtractionCoordinator(
                script: Self.extractionScript,
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

    private let script: String
    private var continuation: CheckedContinuation<ArticleContent?, Error>?
    /// Strong reference keeps the WKWebView alive until extraction completes.
    var webView: WKWebView?
    // RATIONALE: WKWebView.navigationDelegate is weak. This self-reference prevents
    // the coordinator from being deallocated before navigation completes. It is
    // released in cleanup() once the continuation has been resumed.
    private var selfRetain: ExtractionCoordinator?

    init(script: String, continuation: CheckedContinuation<ArticleContent?, Error>) {
        self.script = script
        self.continuation = continuation
        super.init()
        selfRetain = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }
            self.cleanup()

            if let error {
                Self.logger.warning("evaluateJavaScript error: \(error, privacy: .public)")
                self.continuation?.resume(returning: nil)
                self.continuation = nil
                return
            }

            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(ReadabilityResult.self, from: data) else {
                self.continuation?.resume(returning: nil)
                self.continuation = nil
                return
            }

            let content = ArticleContent(
                title: decoded.title,
                byline: decoded.byline.isEmpty ? nil : decoded.byline,
                htmlContent: decoded.content,
                textContent: decoded.textContent
            )
            self.continuation?.resume(returning: content)
            self.continuation = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        cleanup()
        Self.logger.warning("Navigation failed: \(error, privacy: .public)")
        continuation?.resume(throwing: ArticleExtractionError.navigationFailed(error))
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
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

// MARK: - Decodable result

private struct ReadabilityResult: Decodable {
    let title: String
    let byline: String
    let content: String
    let textContent: String
}
