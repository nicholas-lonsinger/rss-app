import Foundation
import os

enum OPMLError: Error, Sendable {
    case parsingFailed(description: String)
    case noBodyFound
    case encodingFailed
}

/// A feed with its associated group names, used for OPML export with category nesting.
struct GroupedFeed: Sendable {
    let feed: SubscribedFeed
    let groupNames: [String]
}

/// The result of parsing an OPML file, including the parsed feed entries and
/// the number of feed outlines that were silently skipped due to invalid xmlUrl values.
struct OPMLParseResult: Sendable {
    let entries: [OPMLFeedEntry]
    /// Number of feed outlines whose `xmlUrl` attribute could not be parsed as a valid URL.
    let parseSkippedCount: Int
}

protocol OPMLServing: Sendable {
    func parseOPML(_ data: Data) throws -> OPMLParseResult
    func generateOPML(from feeds: [SubscribedFeed]) throws -> Data
    func generateOPML(from groupedFeeds: [GroupedFeed]) throws -> Data
}

struct OPMLService: OPMLServing {

    private static let logger = Logger(category: "OPMLService")

    func parseOPML(_ data: Data) throws -> OPMLParseResult {
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

        Self.logger.notice("OPML parsed: \(delegate.entries.count, privacy: .public) feed entries, \(delegate.parseSkippedCount, privacy: .public) skipped due to invalid xmlUrl")
        return OPMLParseResult(entries: delegate.entries, parseSkippedCount: delegate.parseSkippedCount)
    }

    func generateOPML(from feeds: [SubscribedFeed]) throws -> Data {
        let ungrouped = feeds.map { GroupedFeed(feed: $0, groupNames: []) }
        return try generateOPML(from: ungrouped)
    }

    func generateOPML(from groupedFeeds: [GroupedFeed]) throws -> Data {
        Self.logger.debug("generateOPML() called with \(groupedFeeds.count, privacy: .public) feeds")

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let dateString = dateFormatter.string(from: Date())

        // Partition feeds into grouped (by category name) and ungrouped.
        // A feed in multiple groups is duplicated under each category outline.
        var categoryFeeds: [String: [SubscribedFeed]] = [:]
        var ungroupedFeeds: [SubscribedFeed] = []

        for groupedFeed in groupedFeeds {
            if groupedFeed.groupNames.isEmpty {
                ungroupedFeeds.append(groupedFeed.feed)
            } else {
                for groupName in groupedFeed.groupNames {
                    categoryFeeds[groupName, default: []].append(groupedFeed.feed)
                }
            }
        }

        var xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head>
                <title>RSS Subscriptions</title>
                <dateCreated>\(xmlEscape(dateString))</dateCreated>
              </head>
              <body>

            """

        // Emit category outlines in alphabetical order for deterministic output.
        for categoryName in categoryFeeds.keys.sorted() {
            guard let feeds = categoryFeeds[categoryName] else {
                Self.logger.fault("Category '\(categoryName, privacy: .public)' missing from categoryFeeds despite iterating its keys")
                assertionFailure("Category '\(categoryName)' missing from categoryFeeds despite iterating its keys")
                continue
            }
            xml += "    <outline text=\"\(xmlEscape(categoryName))\">\n"
            for feed in feeds {
                xml += "      <outline text=\"\(xmlEscape(feed.title))\" type=\"rss\""
                xml += " xmlUrl=\"\(xmlEscape(feed.url.absoluteString))\""
                if let siteURL = feed.siteURL {
                    xml += " htmlUrl=\"\(xmlEscape(siteURL.absoluteString))\""
                }
                if !feed.feedDescription.isEmpty {
                    xml += " description=\"\(xmlEscape(feed.feedDescription))\""
                }
                xml += "/>\n"
            }
            xml += "    </outline>\n"
        }

        // Emit ungrouped feeds at the top level.
        for feed in ungroupedFeeds {
            xml += "    <outline text=\"\(xmlEscape(feed.title))\" type=\"rss\""
            xml += " xmlUrl=\"\(xmlEscape(feed.url.absoluteString))\""
            if let siteURL = feed.siteURL {
                xml += " htmlUrl=\"\(xmlEscape(siteURL.absoluteString))\""
            }
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

        Self.logger.notice("Generated OPML with \(groupedFeeds.count, privacy: .public) feeds")
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
    /// Number of feed outlines whose `xmlUrl` attribute could not be parsed as a valid URL.
    var parseSkippedCount = 0

    /// Stack of category names representing the current nesting path.
    /// Only `<outline>` elements inside `<body>` that lack `xmlUrl` are
    /// treated as categories. Feeds nested at any depth inherit only the
    /// nearest (innermost) ancestor category name — deeply nested OPML
    /// is flattened to single-level groups.
    private var categoryStack: [String] = []

    /// Parallel stack tracking whether each `<outline>` open event pushed
    /// a category name. `XMLParser` fires `didEndElement` for both
    /// self-closing `<outline ... />` and closing `</outline>` tags, so
    /// this stack lets us pop `categoryStack` only when closing a category
    /// outline — not a feed outline.
    private var outlinePushedCategory: [Bool] = []

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

            if let xmlUrlString = attributeDict["xmlUrl"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !xmlUrlString.isEmpty {
                // This is a feed outline.
                guard let feedURL = URL(string: xmlUrlString) else {
                    Self.logger.warning("Skipped outline with unparseable xmlUrl: '\(xmlUrlString, privacy: .public)'")
                    parseSkippedCount += 1
                    outlinePushedCategory.append(false)
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

                // Use the nearest ancestor category name (top of the stack).
                let groupName = categoryStack.last

                entries.append(OPMLFeedEntry(
                    title: title,
                    feedURL: feedURL,
                    siteURL: siteURL,
                    description: description,
                    groupName: groupName
                ))

                outlinePushedCategory.append(false)
            } else {
                // This is a category outline — push its name onto the stack.
                let categoryName = attributeDict["text"]
                    ?? attributeDict["title"]
                    ?? ""
                if !categoryName.isEmpty {
                    categoryStack.append(categoryName)
                    outlinePushedCategory.append(true)
                } else {
                    Self.logger.warning("Skipped category outline with empty name at line \(parser.lineNumber, privacy: .public) — nested feeds will be ungrouped")
                    outlinePushedCategory.append(false)
                }
            }

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        guard elementName == "outline", foundBody else { return }
        guard let pushedCategory = outlinePushedCategory.popLast() else {
            Self.logger.warning("Outline stack underflow in didEndElement — remaining group assignments may be incorrect")
            return
        }
        if pushedCategory {
            categoryStack.removeLast()
        }
    }
}
