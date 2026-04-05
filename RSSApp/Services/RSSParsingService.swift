import Foundation
import os

enum RSSParsingError: Error, Sendable {
    case parsingFailed(description: String)
    case noChannelFound
}

struct RSSParsingService: Sendable {

    private static let logger = Logger(category: "RSSParsingService")

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
            Self.logger.error("No <channel> (RSS) or <feed> (Atom) element found in feed")
            throw RSSParsingError.noChannelFound
        }

        let imageURL: URL?
        if let urlString = delegate.channelImageURL {
            imageURL = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            imageURL = nil
        }

        let feed = RSSFeed(
            title: HTMLUtilities.decodeHTMLEntities(
                delegate.channelTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            link: URL(string: delegate.channelLink.trimmingCharacters(in: .whitespacesAndNewlines)),
            feedDescription: HTMLUtilities.decodeHTMLEntities(
                delegate.channelDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            articles: delegate.articles,
            lastUpdated: delegate.channelUpdated,
            imageURL: imageURL
        )

        Self.logger.notice("Feed parsed: '\(feed.title, privacy: .public)' with \(feed.articles.count, privacy: .public) articles")
        return feed
    }
}

// MARK: - XMLParser Delegate

// RATIONALE: @unchecked Sendable is safe because the delegate is created and consumed
// synchronously within a single parse() call and never escapes that scope.
private final class RSSParserDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {

    private static let logger = Logger(category: "RSSParserDelegate")

    var foundChannel = false
    var channelTitle = ""
    var channelLink = ""
    var channelDescription = ""
    var channelUpdated: Date?
    var channelImageURL: String?
    var articles: [Article] = []

    private var isInsideItem = false
    private var isInsideChannelImage = false
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
    private var itemAuthor = ""
    private var itemCategories: [String] = []

    // Atom author nesting: <author><name>Text</name></author>
    private var isInsideAuthor = false

    // Tracks whether the current <category> had a term attribute (Atom style)
    // to prevent double-appending when text content also exists.
    private var categoryHandledByAttribute = false

    // XHTML content reconstruction: when <content type="xhtml"> or <summary type="xhtml">
    // is encountered, inner XML elements must be serialized back to HTML rather than parsed
    // as feed structure. Grouped into a struct so enter/exit are single-assignment operations.
    private var xhtmlState: XHTMLState?

    private struct XHTMLState {
        enum Target {
            case content
            case summary

            var closingElementName: String {
                switch self {
                case .content: "content"
                case .summary: "summary"
                }
            }
        }

        var target: Target
        var depth = 0
        var buffer = ""
    }

    private static let htmlVoidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img",
        "input", "link", "meta", "param", "source", "track", "wbr",
    ]

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = qualifiedName ?? elementName

        // XHTML reconstruction: serialize inner elements as HTML
        if xhtmlState != nil {
            xhtmlState!.depth += 1
            // RATIONALE: Atom spec requires <content type="xhtml"> to contain exactly one
            // wrapper <div xmlns="http://www.w3.org/1999/xhtml">. We skip it at depth 1
            // so only its inner content is captured.
            if xhtmlState!.depth > 1 {
                xhtmlState!.buffer += "<\(elementName)"
                for (key, value) in attributeDict where key != "xmlns" {
                    xhtmlState!.buffer += " \(key)=\"\(HTMLUtilities.escapeAttribute(value))\""
                }
                if Self.htmlVoidElements.contains(elementName.lowercased()) {
                    xhtmlState!.buffer += " />"
                } else {
                    xhtmlState!.buffer += ">"
                }
            }
            return
        }

        currentElement = name
        textBuffer = ""

        switch name {
        case "channel", "feed":
            foundChannel = true

        case "image":
            if !isInsideItem {
                isInsideChannelImage = true
            }

        case "item", "entry":
            isInsideItem = true
            itemTitle = ""
            itemLink = ""
            itemDescription = ""
            itemGuid = ""
            itemPubDate = ""
            itemThumbnailURL = nil
            itemEnclosureURL = nil
            itemAuthor = ""
            itemCategories = []
            isInsideAuthor = false
            categoryHandledByAttribute = false

        case "author":
            if isInsideItem {
                isInsideAuthor = true
            }

        case "link":
            // RATIONALE: Atom uses self-closing <link rel="alternate" href="URL"/> while
            // RSS uses <link>URL</link> text content. Extracting href here handles Atom;
            // RSS <link> elements carry no href attribute, so the guard below is a no-op
            // for RSS feeds — assignment happens in didEndElement via text content instead.
            let rel = attributeDict["rel"] ?? "alternate"
            if rel == "alternate", let href = attributeDict["href"] {
                if isInsideItem {
                    if itemLink.isEmpty { itemLink = href }
                } else {
                    if channelLink.isEmpty { channelLink = href }
                }
            }
            // Atom enclosure links: <link rel="enclosure" type="image/..." href="URL"/>
            if rel == "enclosure", isInsideItem {
                let type = attributeDict["type"] ?? ""
                if type.hasPrefix("image/"), let href = attributeDict["href"] {
                    if itemEnclosureURL == nil {
                        itemEnclosureURL = href
                    }
                }
            }

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

        case "category":
            // Atom uses <category term="value"/>, RSS uses <category>text</category>
            if isInsideItem, let term = attributeDict["term"] {
                let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    itemCategories.append(trimmed)
                    categoryHandledByAttribute = true
                }
            } else {
                categoryHandledByAttribute = false
            }

        case "content":
            if isInsideItem, attributeDict["type"] == "xhtml" {
                xhtmlState = XHTMLState(target: .content)
            }

        case "summary":
            if isInsideItem, attributeDict["type"] == "xhtml" {
                xhtmlState = XHTMLState(target: .summary)
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if xhtmlState != nil {
            // XMLParser resolves entities before delivering text, so we must re-escape
            // to produce valid HTML (e.g., "&amp;" → "&" from parser → "&amp;" in output).
            xhtmlState!.buffer += HTMLUtilities.escapeHTML(string)
        } else {
            textBuffer += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            if xhtmlState != nil {
                xhtmlState!.buffer += HTMLUtilities.escapeHTML(string)
            } else {
                textBuffer += string
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let name = qualifiedName ?? elementName

        // XHTML reconstruction: close inner elements
        if let state = xhtmlState {
            if name == state.target.closingElementName && state.depth == 0 {
                // End of the XHTML container — flush the reconstructed HTML
                let html = state.buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                switch state.target {
                case .content:
                    if !html.isEmpty {
                        itemDescription = html
                    } else {
                        Self.logger.debug("XHTML content reconstruction produced empty result for '\(self.itemTitle, privacy: .public)'")
                    }
                case .summary:
                    if itemDescription.isEmpty {
                        if !html.isEmpty {
                            itemDescription = html
                        } else {
                            Self.logger.debug("XHTML summary reconstruction produced empty result for '\(self.itemTitle, privacy: .public)'")
                        }
                    }
                }
                xhtmlState = nil
                currentElement = ""
                textBuffer = ""
                return
            }
            let newDepth = state.depth - 1
            if newDepth < 0 {
                Self.logger.warning("XHTML depth underflow at </\(elementName, privacy: .public)> in '\(self.itemTitle, privacy: .public)'")
            }
            xhtmlState!.depth = max(0, newDepth)
            // Close tags for elements deeper than the wrapper <div>, skipping void elements
            if xhtmlState!.depth > 0, !Self.htmlVoidElements.contains(elementName.lowercased()) {
                xhtmlState!.buffer += "</\(elementName)>"
            }
            return
        }

        if isInsideItem {
            switch name {
            case "title":
                if !isInsideAuthor { itemTitle = textBuffer }
            case "link":
                // Only set from text content (RSS style) if non-empty.
                // Also guards against overwriting the href already set in didStartElement
                // for Atom feeds, since Atom <link> elements produce no text content.
                if itemLink.isEmpty, !textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    itemLink = textBuffer
                }
            case "description":
                itemDescription = textBuffer
            case "content:encoded":
                // Prefer content:encoded over description if available
                if !textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    itemDescription = textBuffer
                }
            case "summary":
                // Atom summary; used as description fallback if no RSS <description> was found
                if itemDescription.isEmpty {
                    itemDescription = textBuffer
                }
            case "content":
                // Atom content; treated like RSS content:encoded — overwrites description/summary
                // if non-empty. (XHTML type is handled separately above.)
                if !textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    itemDescription = textBuffer
                }
            case "guid":
                itemGuid = textBuffer
            case "id":
                // Atom entry ID; used as guid fallback. RSS <guid> takes priority if present.
                if itemGuid.isEmpty {
                    itemGuid = textBuffer
                }
            case "pubDate":
                itemPubDate = textBuffer
            case "published":
                itemPubDate = textBuffer
            case "updated":
                // Atom updated date; fallback when neither RSS <pubDate> nor Atom <published> was found
                if itemPubDate.isEmpty {
                    itemPubDate = textBuffer
                }
            case "author":
                // RSS <author> stores plain text; Atom <author> is a container (handled via name)
                isInsideAuthor = false
                let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if itemAuthor.isEmpty, !text.isEmpty {
                    itemAuthor = text
                }
            case "name":
                // Atom <author><name>Text</name></author>
                if isInsideAuthor {
                    let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { itemAuthor = text }
                }
            case "category":
                // RSS <category>text</category> — skip if already handled via term attribute
                if !categoryHandledByAttribute {
                    let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        itemCategories.append(text)
                    }
                }
                categoryHandledByAttribute = false
            case "item", "entry":
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
                if channelLink.isEmpty, !textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    channelLink = textBuffer
                }
            case "description":
                if channelDescription.isEmpty { channelDescription = textBuffer }
            case "subtitle":
                // Atom feed subtitle; used as channel description when no RSS <description> was found
                if channelDescription.isEmpty { channelDescription = textBuffer }
            case "updated", "lastBuildDate":
                if channelUpdated == nil {
                    channelUpdated = Self.parseDate(textBuffer)
                }
            case "url":
                // RSS <image><url>text</url></image>
                if isInsideChannelImage {
                    let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { channelImageURL = trimmed }
                }
            case "image":
                isInsideChannelImage = false
            case "logo":
                // Atom <logo> — highest priority feed image for Atom feeds
                let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { channelImageURL = trimmed }
            case "icon":
                // Atom <icon> — fallback when no <logo> is present
                if channelImageURL == nil {
                    let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { channelImageURL = trimmed }
                }
            default:
                break
            }
        }

        currentElement = ""
        textBuffer = ""
    }

    // MARK: - Article Construction

    private func buildArticle() -> Article {
        let title = HTMLUtilities.decodeHTMLEntities(
            itemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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

        // Author: decode entities, trimmed, nil if empty
        let authorTrimmed = HTMLUtilities.decodeHTMLEntities(
            itemAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        return Article(
            id: id,
            title: title.isEmpty ? "Untitled" : title,
            link: URL(string: linkString),
            articleDescription: rawDescription,
            snippet: snippet,
            publishedDate: Self.parseDate(itemPubDate),
            thumbnailURL: thumbnailURL,
            author: authorTrimmed.isEmpty ? nil : authorTrimmed,
            categories: itemCategories
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

        // Fallback: DateFormatter's Z specifier matches -0400 (RFC 822) but not the
        // colon-separated -04:00 form required by RFC 3339/Atom. ISO8601DateFormatter
        // with .withInternetDateTime handles the colon form (e.g., "2026-04-01T15:06:21-04:00").
        if let date = ISO8601Formatters.standard.date(from: trimmed) {
            return date
        }
        return ISO8601Formatters.fractional.date(from: trimmed)
    }

    // RATIONALE: nonisolated(unsafe) is safe because these formatters are initialized
    // once via static let and never mutated after initialization — only date(from:) is called.
    private enum ISO8601Formatters {
        nonisolated(unsafe) static let standard: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()

        nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
    }
}
