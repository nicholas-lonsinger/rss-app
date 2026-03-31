import Foundation
import os

enum RSSParsingError: Error, Sendable {
    case parsingFailed(description: String)
    case noChannelFound
}

struct RSSParsingService: Sendable {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "RSSParsingService"
    )

    static let snippetMaxLength = 200

    func parse(_ data: Data) throws -> RSSFeed {
        Self.logger.debug("parse() called with \(data.count, privacy: .public) bytes")

        let delegate = RSSParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        guard parser.parse() else {
            let errorDescription = parser.parserError?.localizedDescription ?? "Unknown parsing error"
            Self.logger.error("XML parsing failed: \(errorDescription, privacy: .public)")
            throw RSSParsingError.parsingFailed(description: errorDescription)
        }

        guard delegate.foundChannel else {
            Self.logger.error("No <channel> element found in feed")
            throw RSSParsingError.noChannelFound
        }

        let feed = RSSFeed(
            title: delegate.channelTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            link: URL(string: delegate.channelLink.trimmingCharacters(in: .whitespacesAndNewlines)),
            feedDescription: delegate.channelDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            articles: delegate.articles
        )

        Self.logger.notice("Feed parsed: '\(feed.title, privacy: .public)' with \(feed.articles.count, privacy: .public) articles")
        return feed
    }
}

// MARK: - XMLParser Delegate

// RATIONALE: @unchecked Sendable is safe because the delegate is created and consumed
// synchronously within a single parse() call and never escapes that scope.
private final class RSSParserDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {

    var foundChannel = false
    var channelTitle = ""
    var channelLink = ""
    var channelDescription = ""
    var articles: [Article] = []

    private var isInsideItem = false
    private var currentElement = ""
    private var textBuffer = ""

    // Per-item accumulators
    private var itemTitle = ""
    private var itemLink = ""
    private var itemDescription = ""
    private var itemGuid = ""
    private var itemPubDate = ""
    private var itemThumbnailURL: String?
    private var itemEnclosureURL: String?

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = qualifiedName ?? elementName
        currentElement = name
        textBuffer = ""

        switch name {
        case "channel":
            foundChannel = true

        case "item":
            isInsideItem = true
            itemTitle = ""
            itemLink = ""
            itemDescription = ""
            itemGuid = ""
            itemPubDate = ""
            itemThumbnailURL = nil
            itemEnclosureURL = nil

        case "media:thumbnail":
            if isInsideItem, itemThumbnailURL == nil {
                itemThumbnailURL = attributeDict["url"]
            }

        case "media:content":
            if isInsideItem, itemThumbnailURL == nil {
                let medium = attributeDict["medium"] ?? ""
                let type = attributeDict["type"] ?? ""
                if medium == "image" || type.hasPrefix("image/") {
                    itemThumbnailURL = attributeDict["url"]
                }
            }

        case "enclosure":
            if isInsideItem {
                let type = attributeDict["type"] ?? ""
                if type.hasPrefix("image/") {
                    itemEnclosureURL = attributeDict["url"]
                }
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            textBuffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let name = qualifiedName ?? elementName

        if isInsideItem {
            switch name {
            case "title":
                itemTitle = textBuffer
            case "link":
                itemLink = textBuffer
            case "description":
                itemDescription = textBuffer
            case "content:encoded":
                // Prefer content:encoded over description if available
                if !textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    itemDescription = textBuffer
                }
            case "guid":
                itemGuid = textBuffer
            case "pubDate":
                itemPubDate = textBuffer
            case "item":
                articles.append(buildArticle())
                isInsideItem = false
            default:
                break
            }
        } else {
            switch name {
            case "title":
                if channelTitle.isEmpty { channelTitle = textBuffer }
            case "link":
                if channelLink.isEmpty { channelLink = textBuffer }
            case "description":
                if channelDescription.isEmpty { channelDescription = textBuffer }
            default:
                break
            }
        }

        currentElement = ""
        textBuffer = ""
    }

    // MARK: - Article Construction

    private func buildArticle() -> Article {
        let title = itemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkString = itemLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDescription = itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let guid = itemGuid.trimmingCharacters(in: .whitespacesAndNewlines)

        // ID: guid → link → hash of title+description
        let id: String
        if !guid.isEmpty {
            id = guid
        } else if !linkString.isEmpty {
            id = linkString
        } else {
            id = String(abs("\(title)\(rawDescription)".hashValue))
        }

        // Snippet: strip HTML and truncate
        let plainText = HTMLUtilities.stripHTML(rawDescription)
        let snippet: String
        if plainText.count > RSSParsingService.snippetMaxLength {
            let endIndex = plainText.index(plainText.startIndex, offsetBy: RSSParsingService.snippetMaxLength)
            snippet = String(plainText[..<endIndex]) + "…"
        } else {
            snippet = plainText
        }

        // Thumbnail: media:thumbnail → media:content → enclosure → first img in description
        let thumbnailURL: URL?
        if let urlString = itemThumbnailURL {
            thumbnailURL = URL(string: urlString)
        } else if let urlString = itemEnclosureURL {
            thumbnailURL = URL(string: urlString)
        } else {
            thumbnailURL = HTMLUtilities.extractFirstImageURL(from: rawDescription)
        }

        return Article(
            id: id,
            title: title.isEmpty ? "Untitled" : title,
            link: URL(string: linkString),
            articleDescription: rawDescription,
            snippet: snippet,
            publishedDate: Self.parseDate(itemPubDate),
            thumbnailURL: thumbnailURL
        )
    }

    // MARK: - Date Parsing

    private static func parseDate(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        ]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    }
}
