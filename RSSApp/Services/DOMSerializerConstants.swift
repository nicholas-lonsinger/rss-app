import Foundation

/// Shared constants for the DOM serializer JS bridge.
///
/// Centralizes the message handler name and JS function call string
/// used by both `ArticleReaderWebView` and `ArticleExtractionService`.
enum DOMSerializerConstants {
    /// WKScriptMessageHandler name registered for early extraction.
    static let messageHandlerName = "domSerialized"
    /// JavaScript expression to invoke the serializer.
    static let serializerCall = "serializeDOM()"
}
