import Testing
import Foundation
@testable import RSSApp

@Suite("FeedViewModel Tests")
struct FeedViewModelTests {

    @Test("loadFeed populates articles on success")
    @MainActor
    func loadFeedSuccess() async {
        let mock = MockFeedFetchingService()
        mock.feedToReturn = TestFixtures.makeFeed(articles: [
            TestFixtures.makeArticle(id: "1", title: "Article 1"),
            TestFixtures.makeArticle(id: "2", title: "Article 2"),
        ])

        let viewModel = FeedViewModel(feedFetching: mock)
        await viewModel.loadFeed()

        #expect(viewModel.articles.count == 2)
        #expect(viewModel.articles[0].title == "Article 1")
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test("loadFeed sets errorMessage on failure")
    @MainActor
    func loadFeedFailure() async {
        let mock = MockFeedFetchingService()
        mock.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 500)

        let viewModel = FeedViewModel(feedFetching: mock)
        await viewModel.loadFeed()

        #expect(viewModel.articles.isEmpty)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.isLoading == false)
    }

    @Test("loadFeed clears previous error on retry")
    @MainActor
    func loadFeedClearsPreviousError() async {
        let mock = MockFeedFetchingService()
        mock.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 500)

        let viewModel = FeedViewModel(feedFetching: mock)
        await viewModel.loadFeed()
        #expect(viewModel.errorMessage != nil)

        // Retry with success
        mock.errorToThrow = nil
        mock.feedToReturn = TestFixtures.makeFeed(articles: [
            TestFixtures.makeArticle(),
        ])
        await viewModel.loadFeed()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.articles.count == 1)
    }

    @Test("loadFeed replaces articles on refresh")
    @MainActor
    func loadFeedReplacesArticles() async {
        let mock = MockFeedFetchingService()
        mock.feedToReturn = TestFixtures.makeFeed(articles: [
            TestFixtures.makeArticle(id: "1"),
        ])

        let viewModel = FeedViewModel(feedFetching: mock)
        await viewModel.loadFeed()
        #expect(viewModel.articles.count == 1)

        // Refresh with different articles
        mock.feedToReturn = TestFixtures.makeFeed(articles: [
            TestFixtures.makeArticle(id: "a"),
            TestFixtures.makeArticle(id: "b"),
            TestFixtures.makeArticle(id: "c"),
        ])
        await viewModel.loadFeed()
        #expect(viewModel.articles.count == 3)
    }

    @Test("isLoading is false after loadFeed completes")
    @MainActor
    func isLoadingAfterCompletion() async {
        let mock = MockFeedFetchingService()
        mock.feedToReturn = TestFixtures.makeFeed()

        let viewModel = FeedViewModel(feedFetching: mock)
        #expect(viewModel.isLoading == false)

        await viewModel.loadFeed()
        #expect(viewModel.isLoading == false)
    }
}
