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

    /// Parses a feed date string into an absolute `Date`, prioritizing formats with
    /// explicit timezone information to avoid ambiguity.
    ///
    /// Parsing strategy, in order:
    /// 1. `ISO8601DateFormatter` with `.withInternetDateTime` and/or `.withFractionalSeconds`
    ///    — covers RFC 3339 / Atom formats. This is the correct format for Atom feeds and
    ///    the most common format for modern RSS, so it's the common-case fast path.
    /// 2. A list of explicit `DateFormatter` patterns covering RFC 822 / RFC 2822 variants
    ///    and their common real-world deviations (named zones, missing seconds, single-digit
    ///    day, space separator instead of `T`, etc.) — all of which include an explicit zone.
    /// 3. Zone-less fallback: the same patterns without a trailing zone specifier, interpreted
    ///    as UTC with a `.warning` log. This produces *some* valid `Date` for feeds that emit
    ///    ambiguous timestamps rather than silently discarding them. The alternative —
    ///    returning `nil` — hides the feed's age entirely in the UI.
    ///
    /// All successful parses are sanity-checked against a plausible date range. Inputs that
    /// parse to an impossible absolute moment (e.g., `DateFormatter`'s `yyyy` "year of era"
    /// accepting `"26"` as year 26 AD) are rejected to prevent corrupt timestamps from
    /// poisoning cross-feed sorting and retention. See GitHub issue #208 for the motivating
    /// bug report on incorrect article timestamps.
    private static func parseDate(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. ISO 8601 / RFC 3339 — most modern feeds use this. Handles `...Z`,
        //    `...+0000`, `...-07:00`, and fractional-second variants.
        if let date = ISO8601Formatters.standard.date(from: trimmed) {
            return sanityChecked(date, input: trimmed, source: "ISO8601")
        }
        if let date = ISO8601Formatters.fractional.date(from: trimmed) {
            return sanityChecked(date, input: trimmed, source: "ISO8601 fractional")
        }

        // 2. Explicit-zone DateFormatter patterns (RFC 822 / RFC 2822 and common variants).
        //    Every format here must end in a zone specifier; zone-less formats are handled
        //    in the fallback block below with clearly documented UTC assumption and logging.
        //    The formatter's `timeZone` is pinned to UTC as defense-in-depth so that any
        //    format that fails to read a zone from the input (rather than falling through
        //    to the zoneless block) won't silently inherit the device's local zone.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")

        for format in Self.zonedDateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return sanityChecked(date, input: trimmed, source: "zoned '\(format)'")
            }
        }

        // 3. Zone-less fallback. The input doesn't match any explicit-zone format; the
        //    publisher almost certainly omitted zone information. Interpreting as UTC is
        //    a documented fallback — not a silent guess. We log a warning so these feeds
        //    are visible in diagnostic output.
        for format in Self.zonelessDateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                Self.logger.warning(
                    "Feed date '\(trimmed, privacy: .public)' had no timezone; interpreted as UTC (format '\(format, privacy: .public)')"
                )
                return sanityChecked(date, input: trimmed, source: "zoneless '\(format)'")
            }
        }

        Self.logger.warning(
            "Feed date '\(trimmed, privacy: .public)' did not match any known format; returning nil"
        )
        return nil
    }

    /// Plausible-date window used to reject obviously-wrong parse results. The lower bound
    /// predates RSS itself, so any feed date older than this is almost certainly a parser
    /// artifact (e.g., `DateFormatter`'s `yyyy` accepting `"26"` as year 26 AD). The upper
    /// bound allows a day of slop for publishers with clock skew or scheduled posts.
    private static let minimumPlausibleDate: Date = {
        var components = DateComponents()
        components.year = 1990
        components.month = 1
        components.day = 1
        components.timeZone = TimeZone(identifier: "UTC")
        // RATIONALE: Calendar.date(from:) on a hardcoded valid DateComponents can only
        // return nil under pathological calendar misconfiguration; distantPast is a safe
        // fallback that still allows all real-world feeds through.
        return Calendar(identifier: .gregorian).date(from: components) ?? Date.distantPast
    }()

    /// Validates that a parsed `Date` falls within a plausible window. Returns the date
    /// if it passes and `nil` (with a `.warning` log) if it does not.
    private static func sanityChecked(_ date: Date, input: String, source: String) -> Date? {
        let upperBound = Date().addingTimeInterval(24 * 60 * 60) // now + 1 day of slop
        if date < Self.minimumPlausibleDate || date > upperBound {
            Self.logger.warning(
                "Rejected out-of-range parsed date \(date, privacy: .public) from input '\(input, privacy: .public)' (source: \(source, privacy: .public))"
            )
            return nil
        }
        return date
    }

    /// Date formats that include an explicit timezone specifier. Ordered roughly by
    /// expected frequency (RFC 822 numeric-offset forms first). The loop tries each format
    /// in order and stops on the first match, so ordering affects parse cost for
    /// non-matching inputs but not correctness.
    private static let zonedDateFormats: [String] = [
        // RFC 822 / RFC 2822 with numeric offset (most common in RSS)
        "EEE, dd MMM yyyy HH:mm:ss Z",
        // RFC 822 with named timezone (e.g., "GMT", "EST", "PDT")
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        // Single-digit day variant (appears in real RFC 822 feeds)
        "EEE, d MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss zzz",
        // Without weekday (seen in the wild)
        "dd MMM yyyy HH:mm:ss Z",
        "dd MMM yyyy HH:mm:ss zzz",
        "d MMM yyyy HH:mm:ss Z",
        "d MMM yyyy HH:mm:ss zzz",
        // Without seconds (RFC 2822/5322 permits this; rare but appears in some wire formats)
        "EEE, dd MMM yyyy HH:mm Z",
        "EEE, dd MMM yyyy HH:mm zzz",
        // ISO 8601 with 'T' separator and numeric zone. These are defense-in-depth safety
        // nets for ISO 8601-ish inputs that ISO8601DateFormatter rejects (e.g., unusual
        // fractional-seconds precision or minor whitespace quirks).
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        // ISO 8601 with space separator instead of 'T' (common in SQL-flavored feeds)
        "yyyy-MM-dd HH:mm:ssZ",
        "yyyy-MM-dd HH:mm:ss Z",
        "yyyy-MM-dd HH:mm:ss zzz",
    ]

    /// Date formats *without* a timezone specifier. These are attempted last, with the
    /// formatter's `timeZone` forced to UTC. A warning is logged whenever one of these
    /// matches because the resulting `Date` is necessarily an educated guess.
    private static let zonelessDateFormats: [String] = [
        "EEE, dd MMM yyyy HH:mm:ss",
        "EEE, dd MMM yyyy HH:mm",
        "dd MMM yyyy HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd",
    ]

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
