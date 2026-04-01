import Foundation
import os

/// Scores DOM nodes to identify the most likely article content container.
///
/// The algorithm is adapted from Mozilla's Readability.js:
/// 1. Prune nodes matching unlikely patterns (nav, sidebar, footer, ads)
/// 2. Find scorable elements (`<p>`, `<pre>`, `<td>`, `<section>`, `<h2>`-`<h6>`, div-as-paragraph)
///    and propagate scores to ancestors with decay, weighted by tag type and class/id signals
/// 3. Penalize high link-density nodes
/// 4. Select the top-scoring candidate
enum CandidateScorer {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "CandidateScorer"
    )

    // MARK: - Public API

    /// Identifies the best content-containing node in the DOM tree.
    ///
    /// Returns the winning `DOMNode` and its score, or `nil` if no viable candidate is found.
    static func findTopCandidate(in body: DOMNode) -> ScoredCandidate? {
        var scores: [ObjectIdentifier: Double] = [:]
        var nodeMap: [ObjectIdentifier: NodeWrapper] = [:]

        // Phase 1: Build a wrapped tree, pruning unlikely nodes.
        let wrappedRoot = wrap(body)

        // Phase 2: Find and score scorable elements.
        let scorables = findScorableElements(in: wrappedRoot)

        guard !scorables.isEmpty else {
            logger.debug("No scorable elements found")
            return nil
        }

        // Initialize candidate scores for scorable ancestors.
        for scorable in scorables {
            guard scorable.node.textLength >= 25 else { continue }

            let contentScore = computeContentScore(for: scorable.node)

            // Propagate to ancestors (up to 5 levels).
            var ancestor: NodeWrapper? = scorable.parent
            var level = 0
            while let current = ancestor, level < 5 {
                let id = current.id
                if nodeMap[id] == nil {
                    nodeMap[id] = current
                    scores[id] = initializeScore(for: current.node)
                }

                let divisor: Double
                switch level {
                case 0: divisor = 1.0
                case 1: divisor = 2.0
                default: divisor = Double(level) * 3.0
                }
                scores[id, default: 0] += contentScore / divisor

                ancestor = current.parent
                level += 1
            }
        }

        // Phase 3: Apply link density penalty.
        for (id, score) in scores {
            guard let wrapper = nodeMap[id] else { continue }
            let linkDensity = wrapper.node.linkDensity
            scores[id] = score * (1.0 - linkDensity)
        }

        // Phase 4: Select top candidate.
        guard let (topId, topScore) = scores.max(by: { $0.value < $1.value }),
              let topWrapper = nodeMap[topId] else {
            logger.debug("No candidates scored above zero")
            return nil
        }

        logger.debug(
            "Top candidate: <\(topWrapper.node.tagName, privacy: .public)> id='\(topWrapper.node.identifier, privacy: .public)' cls='\(topWrapper.node.className, privacy: .public)' score=\(topScore, privacy: .public)"
        )

        return ScoredCandidate(node: topWrapper.node, score: topScore)
    }

    // MARK: - Types

    struct ScoredCandidate: Sendable {
        let node: DOMNode
        let score: Double
    }

    // MARK: - Pruning

    // RATIONALE: These regex statics use `nonisolated(unsafe)` because `Regex` is not
    // `Sendable`, but these are immutable after initialization and only read concurrently.
    // `try!` is acceptable because the patterns are compile-time string literals validated
    // by test coverage; invalid regex here is a developer error caught at first test run.

    /// Regex matching class/id values that are unlikely to contain article content.
    nonisolated(unsafe) private static let unlikelyPattern = try! Regex(
        "banner|breadcrumb|combx|comment|community|cover-wrap|disqus|extra|footer|gdpr"
        + "|header|legends|menu|related|remark|replies|rss|shoutbox|sidebar|skyscraper"
        + "|social|sponsor|supplemental|ad-break|agegate|pagination|pager|popup|yom-hierarchical"
        + "|widget|nav|navbar|navigation"
    ).ignoresCase()

    /// Regex matching class/id values that suggest the node might be content after all.
    nonisolated(unsafe) private static let okMaybePattern = try! Regex(
        "and|article|body|column|content|main|shadow|entry|post|text|blog|story"
    ).ignoresCase()

    /// ARIA roles that indicate non-content regions.
    private static let unlikelyRoles: Set<String> = [
        "menu", "menubar", "complementary", "navigation",
        "alert", "alertdialog", "dialog", "banner", "contentinfo",
    ]

    /// Tags that are block-level and thus prevent a div from being treated as a paragraph.
    private static let blockTags: Set<String> = [
        "article", "aside", "blockquote", "details", "dialog", "dd", "div", "dl",
        "dt", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2",
        "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "li", "main", "nav",
        "ol", "p", "pre", "section", "summary", "table", "ul",
    ]

    /// Returns `true` if this node should be pruned from candidate consideration.
    private static func shouldPrune(_ node: DOMNode) -> Bool {
        if !node.isVisible { return true }

        if let role = node.role, unlikelyRoles.contains(role) { return true }

        let matchString = node.className + " " + node.identifier
        guard !matchString.trimmingCharacters(in: .whitespaces).isEmpty else { return false }

        let isUnlikely = matchString.contains(unlikelyPattern)
        let isMaybe = matchString.contains(okMaybePattern)

        if isUnlikely && !isMaybe && node.tagName != "body" {
            return true
        }

        return false
    }

    // MARK: - Wrapped Tree

    /// Wraps DOMNode into a reference type with parent pointers and pruning applied.
    private final class NodeWrapper {
        let node: DOMNode
        lazy var id: ObjectIdentifier = ObjectIdentifier(self)
        weak var parent: NodeWrapper?
        var children: [NodeWrapper] = []

        init(node: DOMNode, parent: NodeWrapper?) {
            self.node = node
            self.parent = parent
        }
    }

    private static func wrap(_ node: DOMNode, parent: NodeWrapper? = nil) -> NodeWrapper {
        let wrapper = NodeWrapper(node: node, parent: parent)
        for child in node.children {
            guard !child.isText else {
                // Text nodes don't need wrapping for candidate scoring;
                // they're accessed via the parent's textContent.
                continue
            }
            guard !shouldPrune(child) else { continue }
            let childWrapper = wrap(child, parent: wrapper)
            wrapper.children.append(childWrapper)
        }
        return wrapper
    }

    // MARK: - Scorable Elements

    /// Tags whose content directly contributes to scoring.
    private static let scorableTags: Set<String> = [
        "p", "pre", "td", "section",
        "h2", "h3", "h4", "h5", "h6",
    ]

    /// Finds elements that should be scored for content.
    ///
    /// In addition to standard scorable tags, divs that contain no block-level
    /// children are treated as pseudo-paragraphs (matching Readability's behavior).
    private static func findScorableElements(in root: NodeWrapper) -> [NodeWrapper] {
        var result: [NodeWrapper] = []
        collectScorables(root, into: &result)
        return result
    }

    private static func collectScorables(_ wrapper: NodeWrapper, into result: inout [NodeWrapper]) {
        let tag = wrapper.node.tagName

        if scorableTags.contains(tag) {
            result.append(wrapper)
        } else if tag == "div" && !containsBlockChild(wrapper.node) {
            result.append(wrapper)
        }

        for child in wrapper.children {
            collectScorables(child, into: &result)
        }
    }

    private static func containsBlockChild(_ node: DOMNode) -> Bool {
        node.children.contains { blockTags.contains($0.tagName) }
    }

    // MARK: - Scoring

    /// Computes the base content score for a scorable element.
    private static func computeContentScore(for node: DOMNode) -> Double {
        var score: Double = 1.0
        score += Double(node.commaCount)
        score += min(Double(node.textLength) / 100.0, 3.0)
        return score
    }

    /// Initializes the score for a candidate ancestor node based on tag and class/id signals.
    private static func initializeScore(for node: DOMNode) -> Double {
        var score = tagWeight(for: node.tagName)
        score += classIdWeight(for: node)
        return score
    }

    /// Score weight based on tag name.
    private static func tagWeight(for tag: String) -> Double {
        switch tag {
        case "article": return 10
        case "div": return 5
        case "pre", "td", "blockquote": return 3
        case "address", "ol", "ul", "dl", "dd", "dt", "li", "form": return -3
        case "h1", "h2", "h3", "h4", "h5", "h6", "th": return -5
        default: return 0
        }
    }

    /// Regex matching positive class/id patterns.
    nonisolated(unsafe) private static let positivePattern = try! Regex(
        "article|body|content|entry|hentry|h-entry|main|page|pagination|post|text|blog|story"
    ).ignoresCase()

    /// Regex matching negative class/id patterns.
    nonisolated(unsafe) private static let negativePattern = try! Regex(
        "hidden|banner|combx|comment|com-|contact|foot|footer|footnote"
        + "|gdpr|masthead|media|meta|outbrain|promo|related|scroll"
        + "|share|shoutbox|sidebar|skyscraper|sponsor|shopping"
        + "|tags|tool|widget|nav|navbar"
    ).ignoresCase()

    /// Score weight based on class and id content.
    private static func classIdWeight(for node: DOMNode) -> Double {
        let matchString = node.className + " " + node.identifier
        var weight: Double = 0

        if matchString.contains(positivePattern) {
            weight += 25
        }
        if matchString.contains(negativePattern) {
            weight -= 25
        }

        return weight
    }
}
