import Foundation
import os

enum OPMLError: Error, Sendable {
    case parsingFailed(description: String)
    case noBodyFound
    case encodingFailed
}

protocol OPMLServing: Sendable {
    func parseOPML(_ data: Data) throws -> [OPMLFeedEntry]
    func generateOPML(from feeds: [SubscribedFeed]) throws -> Data
}

struct OPMLService: OPMLServing {

    private static let logger = Logger(category: "OPMLService")

    func parseOPML(_ data: Data) throws -> [OPMLFeedEntry] {
        Self.logger.debug("parseOPML() called with \(data.count, privacy: .public) bytes")

        let delegate = OPMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        guard parser.parse() else {
            let errorDescription = parser.parserError?.localizedDescription ?? "Unknown parsing error"
            Self.logger.error("XML parsing failed: \(errorDescription, privacy: .public)")
            throw OPMLError.parsingFailed(description: errorDescription)
        }

        guard delegate.foundBody else {
            Self.logger.error("No <body> element found in OPML")
            throw OPMLError.noBodyFound
        }

        Self.logger.notice("OPML parsed: \(delegate.entries.count, privacy: .public) feed entries")
        return delegate.entries
    }

    func generateOPML(from feeds: [SubscribedFeed]) throws -> Data {
        Self.logger.debug("generateOPML() called with \(feeds.count, privacy: .public) feeds")

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let dateString = dateFormatter.string(from: Date())

        var xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head>
                <title>RSS Subscriptions</title>
                <dateCreated>\(xmlEscape(dateString))</dateCreated>
              </head>
              <body>

            """

        for feed in feeds {
            xml += "    <outline text=\"\(xmlEscape(feed.title))\" type=\"rss\""
            xml += " xmlUrl=\"\(xmlEscape(feed.url.absoluteString))\""
            if !feed.feedDescription.isEmpty {
                xml += " description=\"\(xmlEscape(feed.feedDescription))\""
            }
            xml += "/>\n"
        }

        xml += """
              </body>
            </opml>

            """

        guard let data = xml.data(using: .utf8) else {
            Self.logger.fault("Failed to encode OPML XML string as UTF-8")
            assertionFailure("Failed to encode OPML XML string as UTF-8")
            throw OPMLError.encodingFailed
        }

        Self.logger.notice("Generated OPML with \(feeds.count, privacy: .public) feeds")
        return data
    }

    // MARK: - Helpers

    private func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - XMLParser Delegate

// RATIONALE: @unchecked Sendable is safe because the delegate is created and consumed
// synchronously within a single parseOPML() call and never escapes that scope.
private final class OPMLParserDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {

    private static let logger = Logger(category: "OPMLParserDelegate")

    var foundBody = false
    var entries: [OPMLFeedEntry] = []

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "body":
            foundBody = true

        case "outline":
            guard foundBody else { return }
            guard let xmlUrlString = attributeDict["xmlUrl"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !xmlUrlString.isEmpty else { return }
            guard let feedURL = URL(string: xmlUrlString) else {
                Self.logger.warning("Skipped outline with unparseable xmlUrl: '\(xmlUrlString, privacy: .public)'")
                return
            }

            let title = attributeDict["text"]
                ?? attributeDict["title"]
                ?? xmlUrlString

            let siteURL: URL?
            if let htmlUrlString = attributeDict["htmlUrl"] {
                siteURL = URL(string: htmlUrlString)
            } else {
                siteURL = nil
            }

            let description = attributeDict["description"] ?? ""

            entries.append(OPMLFeedEntry(
                title: title,
                feedURL: feedURL,
                siteURL: siteURL,
                description: description
            ))

        default:
            break
        }
    }
}
