import Testing
import Foundation
import SwiftData
@testable import RSSApp

@Suite("ArticleSummaryViewModel — pre-extracted content")
@MainActor
struct ArticleSummaryPreExtractionTests {

    private static let sampleContent = ArticleContent(
        title: "Test",
        byline: "Author",
        htmlContent: "<p>Body</p>",
        textContent: "Body"
    )

    @Test("skips extraction when pre-extracted content is provided")
    func skipsExtraction() {
        let mock = MockArticleExtractionService()
        let article = TestFixtures.makeArticle()
        let vm = ArticleSummaryViewModel(
            article: article,
            preExtractedContent: Self.sampleContent,
            extractor: mock
        )

        #expect(vm.extractedContent != nil)
        #expect(vm.extractedContent?.title == "Test")
    }

    @Test("extractedContent is nil when no pre-extracted content provided")
    func noPreExtractedContent() {
        let article = TestFixtures.makeArticle()
        let vm = ArticleSummaryViewModel(article: article, extractor: MockArticleExtractionService())

        #expect(vm.extractedContent == nil)
    }

    @Test("extractedContent set from pre-extraction is available for discussion")
    func preExtractedAvailableForDiscussion() {
        let article = TestFixtures.makeArticle()
        let vm = ArticleSummaryViewModel(
            article: article,
            preExtractedContent: Self.sampleContent,
            extractor: MockArticleExtractionService()
        )

        #expect(vm.extractedContent?.textContent == "Body")
        #expect(vm.extractedContent?.byline == "Author")
    }
}

// MARK: - Staleness Tests

@Suite("ArticleSummaryViewModel — stale content (issue #398)")
@MainActor
struct ArticleSummaryStaleContentTests {

    private static func makeService() throws -> (SwiftDataFeedPersistenceService, ModelContainer) {
        try SwiftDataTestHelpers.makeTestPersistenceService()
    }

    @Test("loadContent sets isContentStale when cached content pre-dates the publisher update")
    func loadContentSetsIsContentStaleWhenCacheIsStale() async throws {
        let (service, container) = try Self.makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Insert article with a known updatedDate.
        let updateTime = Date(timeIntervalSince1970: 1_700_003_600)
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "stale-vm", updatedDate: updateTime)],
            for: feed
        )
        let persistentArticle = try service.articles(for: feed)[0]

        // Cache content extracted *before* the update timestamp.
        let staleContent = PersistentArticleContent(
            title: "Old Title",
            htmlContent: "<p>Old</p>",
            textContent: "Old",
            extractedDate: updateTime.addingTimeInterval(-1800) // 30 min before update
        )
        staleContent.article = persistentArticle
        persistentArticle.content = staleContent

        let article = TestFixtures.makeArticle(id: "stale-vm", updatedDate: updateTime)
        let vm = ArticleSummaryViewModel(
            article: article,
            extractor: MockArticleExtractionService(),
            persistentArticle: persistentArticle,
            persistence: service
        )

        await vm.loadContent()

        #expect(vm.isContentStale == true)
        if case .ready = vm.state { } else {
            Issue.record("Expected .ready state, got \(vm.state)")
        }
    }

    @Test("loadContent does not set isContentStale when cached content is fresh")
    func loadContentDoesNotSetStaleWhenCacheIsFresh() async throws {
        let (service, container) = try Self.makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let updateTime = Date(timeIntervalSince1970: 1_700_000_000)
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "fresh-vm", updatedDate: updateTime)],
            for: feed
        )
        let persistentArticle = try service.articles(for: feed)[0]

        // Cache content extracted *after* the update timestamp.
        let freshContent = PersistentArticleContent(
            title: "Current Title",
            htmlContent: "<p>Current</p>",
            textContent: "Current",
            extractedDate: updateTime.addingTimeInterval(60)
        )
        freshContent.article = persistentArticle
        persistentArticle.content = freshContent

        let article = TestFixtures.makeArticle(id: "fresh-vm", updatedDate: updateTime)
        let vm = ArticleSummaryViewModel(
            article: article,
            extractor: MockArticleExtractionService(),
            persistentArticle: persistentArticle,
            persistence: service
        )

        await vm.loadContent()

        #expect(vm.isContentStale == false)
    }

    @Test("refreshContent replaces stale content and clears isContentStale")
    func refreshContentReplacesStaleContent() async throws {
        let (service, container) = try Self.makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let updateTime = Date(timeIntervalSince1970: 1_700_003_600)
        let link = URL(string: "https://example.com/article")!
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "refresh-vm", link: link, updatedDate: updateTime)],
            for: feed
        )
        let persistentArticle = try service.articles(for: feed)[0]

        // Seed stale cached content.
        let staleContent = PersistentArticleContent(
            title: "Old",
            htmlContent: "<p>Old</p>",
            textContent: "Old",
            extractedDate: updateTime.addingTimeInterval(-3600)
        )
        staleContent.article = persistentArticle
        persistentArticle.content = staleContent

        let freshResult = ArticleContent(
            title: "Fresh Title",
            byline: nil,
            htmlContent: "<p>Fresh</p>",
            textContent: "Fresh"
        )
        let article = TestFixtures.makeArticle(id: "refresh-vm", link: link, updatedDate: updateTime)
        let vm = ArticleSummaryViewModel(
            article: article,
            extractor: MockArticleExtractionService(result: freshResult),
            persistentArticle: persistentArticle,
            persistence: service
        )

        // Prime the view model with stale content.
        await vm.loadContent()
        #expect(vm.isContentStale == true)

        // User taps Refresh.
        await vm.refreshContent()

        #expect(vm.isContentStale == false)
        if case .ready(let content) = vm.state {
            #expect(content.textContent == "Fresh")
        } else {
            Issue.record("Expected .ready state after refresh, got \(vm.state)")
        }
    }

    @Test("refreshContent keeps stale content visible on extraction failure")
    func refreshContentKeepsStaleContentOnFailure() async throws {
        let (service, container) = try Self.makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let updateTime = Date(timeIntervalSince1970: 1_700_003_600)
        let link = URL(string: "https://example.com/article")!
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "refresh-fail", link: link, updatedDate: updateTime)],
            for: feed
        )
        let persistentArticle = try service.articles(for: feed)[0]

        let staleContent = PersistentArticleContent(
            title: "Old",
            htmlContent: "<p>Old</p>",
            textContent: "Old body",
            extractedDate: updateTime.addingTimeInterval(-3600)
        )
        staleContent.article = persistentArticle
        persistentArticle.content = staleContent

        let extractionError = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        let article = TestFixtures.makeArticle(id: "refresh-fail", link: link, updatedDate: updateTime)
        let vm = ArticleSummaryViewModel(
            article: article,
            extractor: MockArticleExtractionService(error: extractionError),
            persistentArticle: persistentArticle,
            persistence: service
        )

        await vm.loadContent()
        #expect(vm.isContentStale == true)

        // Refresh fails — stale content must remain visible.
        await vm.refreshContent()

        // State must still be .ready (not .failed) — user sees the stale body, not an error.
        if case .ready(let content) = vm.state {
            #expect(content.textContent == "Old body")
        } else {
            Issue.record("Expected .ready state with stale body after failed refresh, got \(vm.state)")
        }
        // Banner stays; isContentStale is still true.
        #expect(vm.isContentStale == true)
    }
}
