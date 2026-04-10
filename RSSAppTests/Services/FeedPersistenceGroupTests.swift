import Testing
import Foundation
@testable import RSSApp

/// Tests for the group operations on `MockFeedPersistenceService`.
/// These validate the mock's behavior so test doubles used by ViewModel tests
/// are trustworthy. The SwiftData implementation follows the same contract.
@Suite("FeedPersistence Group Tests")
struct FeedPersistenceGroupTests {

    // MARK: - Group CRUD

    @Test("addGroup and allGroups round-trip")
    @MainActor
    func addGroupRoundTrip() throws {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Tech", sortOrder: 0)
        try mock.addGroup(group)

        let groups = try mock.allGroups()
        #expect(groups.count == 1)
        #expect(groups.first?.name == "Tech")
    }

    @Test("allGroups returns groups sorted by sortOrder")
    @MainActor
    func allGroupsSorted() throws {
        let mock = MockFeedPersistenceService()
        let groupB = PersistentFeedGroup(name: "B", sortOrder: 2)
        let groupA = PersistentFeedGroup(name: "A", sortOrder: 1)
        let groupC = PersistentFeedGroup(name: "C", sortOrder: 0)
        try mock.addGroup(groupB)
        try mock.addGroup(groupA)
        try mock.addGroup(groupC)

        let groups = try mock.allGroups()
        #expect(groups.map(\.name) == ["C", "A", "B"])
    }

    @Test("deleteGroup removes group and its memberships")
    @MainActor
    func deleteGroupCascade() throws {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "ToDelete")
        let feed = TestFixtures.makePersistentFeed()
        mock.feeds = [feed]
        try mock.addGroup(group)
        try mock.addFeed(feed, to: group)

        try mock.deleteGroup(group)

        #expect(try mock.allGroups().isEmpty)
        #expect(mock.memberships.isEmpty)
        #expect(mock.feeds.count == 1) // Feed is NOT deleted
    }

    @Test("renameGroup updates group name")
    @MainActor
    func renameGroup() throws {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Old")
        try mock.addGroup(group)

        try mock.renameGroup(group, to: "New")

        #expect(group.name == "New")
    }

    // MARK: - Membership

    @Test("addFeed creates membership")
    @MainActor
    func addFeedToGroup() throws {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Tech")
        let feed = TestFixtures.makePersistentFeed()
        mock.feeds = [feed]
        try mock.addGroup(group)

        try mock.addFeed(feed, to: group)

        let feeds = try mock.feeds(in: group)
        #expect(feeds.count == 1)
        #expect(feeds.first?.id == feed.id)
    }

    @Test("addFeed is idempotent — duplicate membership is no-op")
    @MainActor
    func addFeedDuplicate() throws {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Tech")
        let feed = TestFixtures.makePersistentFeed()
        try mock.addGroup(group)

        try mock.addFeed(feed, to: group)
        try mock.addFeed(feed, to: group)

        #expect(mock.memberships.count == 1)
    }

    @Test("removeFeed deletes membership")
    @MainActor
    func removeFeedFromGroup() throws {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Tech")
        let feed = TestFixtures.makePersistentFeed()
        try mock.addGroup(group)
        try mock.addFeed(feed, to: group)

        try mock.removeFeed(feed, from: group)

        #expect(try mock.feeds(in: group).isEmpty)
    }

    @Test("groups(for:) returns all groups a feed belongs to")
    @MainActor
    func groupsForFeed() throws {
        let mock = MockFeedPersistenceService()
        let group1 = PersistentFeedGroup(name: "A", sortOrder: 0)
        let group2 = PersistentFeedGroup(name: "B", sortOrder: 1)
        let feed = TestFixtures.makePersistentFeed()
        try mock.addGroup(group1)
        try mock.addGroup(group2)
        try mock.addFeed(feed, to: group1)
        try mock.addFeed(feed, to: group2)

        let groups = try mock.groups(for: feed)
        #expect(groups.count == 2)
        #expect(groups.map(\.name) == ["A", "B"])
    }

    // MARK: - Group article queries

    @Test("articles(in:) returns articles from group feeds only")
    @MainActor
    func articlesInGroup() throws {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Tech")
        try mock.addGroup(group)

        let feedIn = TestFixtures.makePersistentFeed(id: UUID(), title: "In Group")
        let feedOut = TestFixtures.makePersistentFeed(id: UUID(), title: "Outside")
        mock.feeds = [feedIn, feedOut]
        try mock.addFeed(feedIn, to: group)

        let a1 = TestFixtures.makePersistentArticle(articleID: "in1")
        a1.feed = feedIn
        let a2 = TestFixtures.makePersistentArticle(articleID: "out1")
        a2.feed = feedOut
        mock.articlesByFeedID[feedIn.id] = [a1]
        mock.articlesByFeedID[feedOut.id] = [a2]

        let articles = try mock.articles(in: group, cursor: nil, limit: 50, ascending: false)
        #expect(articles.count == 1)
        #expect(articles.first?.articleID == "in1")
    }

    @Test("articles(in:) respects cursor and limit")
    @MainActor
    func articlesInGroupPagination() throws {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Big")
        try mock.addGroup(group)

        let feed = TestFixtures.makePersistentFeed()
        mock.feeds = [feed]
        try mock.addFeed(feed, to: group)

        var articles: [PersistentArticle] = []
        for i in 0..<10 {
            let a = TestFixtures.makePersistentArticle(
                articleID: "a\(i)",
                sortDate: Date(timeIntervalSince1970: Double(1_000_000 - i * 100))
            )
            a.feed = feed
            articles.append(a)
        }
        mock.articlesByFeedID[feed.id] = articles

        let page1 = try mock.articles(in: group, cursor: nil, limit: 3, ascending: false)
        #expect(page1.count == 3)

        // Use the last article from page1 as the cursor for page2
        let cursor = ArticlePaginationCursor(
            sortDate: page1.last!.sortDate,
            articleID: page1.last!.articleID
        )
        let page2 = try mock.articles(in: group, cursor: cursor, limit: 3, ascending: false)
        #expect(page2.count == 3)

        // No overlap
        let ids1 = Set(page1.map(\.articleID))
        let ids2 = Set(page2.map(\.articleID))
        #expect(ids1.isDisjoint(with: ids2))
    }

    @Test("unreadCount(in:) counts unread across group feeds")
    @MainActor
    func unreadCountInGroup() throws {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Tech")
        try mock.addGroup(group)

        let feed = TestFixtures.makePersistentFeed()
        mock.feeds = [feed]
        try mock.addFeed(feed, to: group)

        let a1 = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        a1.feed = feed
        let a2 = TestFixtures.makePersistentArticle(articleID: "a2", isRead: true)
        a2.feed = feed
        mock.articlesByFeedID[feed.id] = [a1, a2]

        let count = try mock.unreadCount(in: group)
        #expect(count == 1)
    }

    @Test("markAllArticlesRead(in:) scopes to group feeds")
    @MainActor
    func markAllReadInGroup() throws {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Scoped")
        try mock.addGroup(group)

        let feedIn = TestFixtures.makePersistentFeed(id: UUID(), title: "In")
        let feedOut = TestFixtures.makePersistentFeed(id: UUID(), title: "Out")
        mock.feeds = [feedIn, feedOut]
        try mock.addFeed(feedIn, to: group)

        let articleIn = TestFixtures.makePersistentArticle(articleID: "in1", isRead: false)
        articleIn.feed = feedIn
        let articleOut = TestFixtures.makePersistentArticle(articleID: "out1", isRead: false)
        articleOut.feed = feedOut
        mock.articlesByFeedID[feedIn.id] = [articleIn]
        mock.articlesByFeedID[feedOut.id] = [articleOut]

        try mock.markAllArticlesRead(in: group)

        #expect(articleIn.isRead == true)
        #expect(articleOut.isRead == false)
    }
}
