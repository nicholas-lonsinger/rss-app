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
    case missingArticleURL
    case navigationFailed(Error)
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

        let serializerJS: String
        do {
            serializerJS = try loadSerializerJS()
        } catch {
            Self.logger.fault("domSerializer.js not available: \(error, privacy: .public)")
            assertionFailure("domSerializer.js not available: \(error)")
            throw ArticleExtractionError.serializerNotFound
        }

        do {
            if let content = try await loadAndExtract(url: url, serializerJS: serializerJS) {
                Self.logger.notice("Native extraction succeeded for \(url.absoluteString, privacy: .public)")
                return content
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.warning(
                "Extraction failed for \(url.absoluteString, privacy: .public): \(error, privacy: .public) — using RSS fallback"
            )
        }

        return ArticleContent.rssFallback(html: fallbackHTML)
    }

    // MARK: - Private

    private func loadSerializerJS() throws -> String {
        guard let scriptURL = Bundle.main.url(forResource: "domSerializer", withExtension: "js") else {
            throw ArticleExtractionError.serializerNotFound
        }
        return try String(contentsOf: scriptURL, encoding: .utf8)
    }

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

            if let keyWindow {
                keyWindow.addSubview(webView)
            } else {
                Self.logger.warning("No key window available — WKWebView delegate callbacks may not fire")
            }

            // 30-second request timeout — if the server is unreachable or stalls,
            // the navigation delegate failure callback resumes the continuation.
            webView.load(URLRequest(url: url, timeoutInterval: 30))

            // Safety timeout: if no delegate callback fires within 35 seconds
            // (e.g., page hangs on subresources), resume the continuation to prevent
            // an indefinite hang. The 35s gives the URLRequest timeout (30s) time to fire first.
            Task { @MainActor [weak coordinator] in
                try? await Task.sleep(for: .seconds(35))
                guard let coordinator, coordinator.continuation != nil else { return }
                Self.logger.warning("Extraction timed out for \(url.absoluteString, privacy: .public)")
                coordinator.resumeAndCleanup(returning: nil)
            }
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
    fileprivate var continuation: CheckedContinuation<ArticleContent?, Error>?
    /// Strong reference keeps the WKWebView alive until extraction completes.
    var webView: WKWebView?
    // RATIONALE: WKWebView.navigationDelegate is weak. This self-reference prevents
    // the coordinator from being deallocated before navigation completes. It is
    // released in resumeAndCleanup() once the continuation has been resumed.
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
        webView.evaluateJavaScript(DOMSerializerConstants.serializerCall) { [weak self] result, error in
            guard let self else { return }

            if let error {
                Self.logger.warning("serializeDOM() error: \(error, privacy: .public)")
                self.resumeAndCleanup(returning: nil)
                return
            }

            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8) else {
                Self.logger.warning("serializeDOM() returned nil or non-string result")
                self.resumeAndCleanup(returning: nil)
                return
            }

            do {
                let dom = try JSONDecoder().decode(SerializedDOM.self, from: data)
                let content = self.contentExtractor.extract(from: dom)
                self.resumeAndCleanup(returning: content)
            } catch {
                Self.logger.warning("DOM JSON decoding failed: \(error, privacy: .public)")
                self.resumeAndCleanup(returning: nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Self.logger.warning("Navigation failed: \(error, privacy: .public)")
        resumeAndCleanup(throwing: ArticleExtractionError.navigationFailed(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Self.logger.warning("Provisional navigation failed: \(error, privacy: .public)")
        resumeAndCleanup(throwing: ArticleExtractionError.navigationFailed(error))
    }

    /// Resumes the continuation with a value, then cleans up.
    fileprivate func resumeAndCleanup(returning content: ArticleContent?) {
        guard let continuation else { return }
        self.continuation = nil
        cleanup()
        continuation.resume(returning: content)
    }

    /// Resumes the continuation with an error, then cleans up.
    private func resumeAndCleanup(throwing error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        cleanup()
        continuation.resume(throwing: error)
    }

    private func cleanup() {
        webView?.removeFromSuperview()
        webView = nil
        selfRetain = nil
    }
}
