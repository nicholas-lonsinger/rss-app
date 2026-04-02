import Foundation
import os

/// Protocol for extracting article content from a serialized DOM.
protocol ContentExtracting: Sendable {
    func extract(from dom: SerializedDOM) -> ArticleContent?
}

/// Orchestrates article content extraction from a serialized DOM tree.
///
/// Pipeline: site-specific extractors → metadata extraction → candidate scoring → content assembly.
struct ContentExtractor: ContentExtracting {

    private static let logger = Logger(
        subsystem: Logger.appSubsystem,
        category: "ContentExtractor"
    )

    /// Site-specific extractors checked before the generic algorithm.
    private let siteExtractors: [any SiteSpecificExtracting]

    init(siteExtractors: [any SiteSpecificExtracting] = []) {
        self.siteExtractors = siteExtractors
    }

    func extract(from dom: SerializedDOM) -> ArticleContent? {
        Self.logger.debug("Extracting content from '\(dom.url, privacy: .public)'")

        // 1. Try site-specific extractors first.
        if let hostname = URL(string: dom.url)?.host {
            for extractor in siteExtractors {
                if extractor.canHandle(hostname: hostname),
                   let content = extractor.extract(from: dom) {
                    Self.logger.notice(
                        "Site-specific extractor matched for '\(hostname, privacy: .public)' (\(content.textContent.count, privacy: .public) chars)"
                    )
                    return content
                }
            }
        }

        // 2. Extract metadata (title, byline).
        let metadata = MetadataExtractor.extract(from: dom)

        // 3. Score candidates and find the best content node.
        guard let candidate = CandidateScorer.findTopCandidate(in: dom.body) else {
            Self.logger.debug("No candidate found in DOM")
            return nil
        }

        // 4. Assemble clean output from the winning subtree.
        let (html, text) = ContentAssembler.assemble(from: candidate.node)

        guard !text.isEmpty else {
            Self.logger.debug("Candidate produced empty text content")
            return nil
        }

        Self.logger.debug(
            "Extraction complete: score=\(candidate.score, privacy: .public), \(text.count, privacy: .public) text chars"
        )

        return ArticleContent(
            title: metadata.title,
            byline: metadata.byline,
            htmlContent: html,
            textContent: text
        )
    }
}
