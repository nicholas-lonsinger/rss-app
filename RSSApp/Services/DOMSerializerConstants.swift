import Foundation
import os

/// Shared constants and helpers for the DOM serializer JS bridge.
///
/// Centralizes the message handler name, JS function call string, and
/// DOM-to-ArticleContent extraction logic used by both
/// `ArticleReaderWebView` and `ArticleExtractionService`.
enum DOMSerializerConstants {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "DOMSerializerConstants"
    )

    /// WKScriptMessageHandler name registered for early extraction.
    static let messageHandlerName = "domSerialized"
    /// JavaScript expression to invoke the serializer.
    static let serializerCall = "serializeDOM()"

    /// Decodes a serialized DOM JSON string and extracts article content.
    ///
    /// Shared by `ExtractionCoordinator` and `ArticleReaderWebView.Coordinator`
    /// to avoid duplicating the JSON → SerializedDOM → ArticleContent pipeline.
    ///
    /// - Returns: Extracted content, or `nil` if the extractor finds no article.
    /// - Throws: `DecodingError` if the JSON is malformed.
    static func extractContent(
        fromJSON jsonString: String,
        using extractor: any ContentExtracting
    ) throws -> ArticleContent? {
        guard let data = jsonString.data(using: .utf8) else {
            logger.fault("String.data(using: .utf8) returned nil — should be unreachable")
            assertionFailure("String.data(using: .utf8) returned nil")
            return nil
        }
        let dom = try JSONDecoder().decode(SerializedDOM.self, from: data)
        return extractor.extract(from: dom)
    }
}
