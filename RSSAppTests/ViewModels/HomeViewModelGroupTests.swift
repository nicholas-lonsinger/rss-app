import Testing
import Foundation
@testable import RSSApp

@Suite("HomeViewModel Group Tests")
struct HomeViewModelGroupTests {

    // MARK: - loadGroups

    @Test("loadGroups populates groups array and unread counts")
    @MainActor
    func loadGroupsSuccess() {
        let mockPersistence = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Tech")
        mockPersistence.groups = [group]

        let feed = TestFixtures.makePersistentFeed()
        mockPersistence.feeds = [feed]
        let unreadArticle = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        unreadArticle.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [unreadArticle]
        let membership = PersistentFeedGroupMembership(feed: feed, group: group)
        mockPersistence.memberships = [membership]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadGroups()

        #expect(viewModel.groups.count == 1)
        #expect(viewModel.groups.first?.name == "Tech")
        #expect(viewModel.groupUnreadCounts[group.id] == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("loadGroups sets error on persistence failure")
    @MainActor
    func loadGroupsError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.groupError = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadGroups()

        #expect(viewModel.groups.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("loadGroups returns empty array when no groups exist")
    @MainActor
    func loadGroupsEmpty() {
        let mockPersistence = MockFeedPersistenceService()
        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadGroups()

        #expect(viewModel.groups.isEmpty)
        #expect(viewModel.groupUnreadCounts.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - addGroup

    @Test("addGroup creates group and reloads list")
    @MainActor
    func addGroupSuccess() {
        let mockPersistence = MockFeedPersistenceService()
        let viewModel = HomeViewModel(persistence: mockPersistence)

        viewModel.addGroup(name: "News")

        #expect(viewModel.groups.count == 1)
        #expect(viewModel.groups.first?.name == "News")
        #expect(viewModel.groups.first?.sortOrder == 0)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("addGroup assigns incrementing sortOrder")
    @MainActor
    func addGroupSortOrder() {
        let mockPersistence = MockFeedPersistenceService()
        let viewModel = HomeViewModel(persistence: mockPersistence)

        viewModel.addGroup(name: "First")
        viewModel.addGroup(name: "Second")

        #expect(viewModel.groups.count == 2)
        #expect(viewModel.groups[0].sortOrder == 0)
        #expect(viewModel.groups[1].sortOrder == 1)
    }

    @Test("addGroup sets error on persistence failure")
    @MainActor
    func addGroupError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.groupError = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.addGroup(name: "Fail")

        #expect(viewModel.groups.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }

    // MARK: - deleteGroup

    @Test("deleteGroup removes group and reloads list")
    @MainActor
    func deleteGroupSuccess() {
        let mockPersistence = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "ToDelete")
        mockPersistence.groups = [group]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadGroups()
        #expect(viewModel.groups.count == 1)

        viewModel.deleteGroup(group)

        #expect(viewModel.groups.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - renameGroup

    @Test("renameGroup updates group name")
    @MainActor
    func renameGroupSuccess() {
        let mockPersistence = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Old Name")
        mockPersistence.groups = [group]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadGroups()

        viewModel.renameGroup(group, to: "New Name")

        #expect(viewModel.groups.first?.name == "New Name")
    }

    // MARK: - markAllArticlesReadInGroup

    @Test("markAllArticlesReadInGroup marks only articles in group feeds")
    @MainActor
    func markAllReadInGroup() {
        let mockPersistence = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Tech")
        mockPersistence.groups = [group]

        let feedInGroup = TestFixtures.makePersistentFeed(id: UUID(), title: "In Group")
        let feedOutside = TestFixtures.makePersistentFeed(id: UUID(), title: "Outside")
        mockPersistence.feeds = [feedInGroup, feedOutside]

        let articleIn = TestFixtures.makePersistentArticle(articleID: "in1", isRead: false)
        articleIn.feed = feedInGroup
        let articleOut = TestFixtures.makePersistentArticle(articleID: "out1", isRead: false)
        articleOut.feed = feedOutside

        mockPersistence.articlesByFeedID[feedInGroup.id] = [articleIn]
        mockPersistence.articlesByFeedID[feedOutside.id] = [articleOut]
        mockPersistence.memberships = [PersistentFeedGroupMembership(feed: feedInGroup, group: group)]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.markAllArticlesReadInGroup(group)

        #expect(articleIn.isRead == true)
        #expect(articleOut.isRead == false)
    }

    // MARK: - groupUnreadCounts

    @Test("groupUnreadCounts reflects unread across multiple feeds in group")
    @MainActor
    func groupUnreadCountMultipleFeeds() {
        let mockPersistence = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Multi")
        mockPersistence.groups = [group]

        let feed1 = TestFixtures.makePersistentFeed(id: UUID(), title: "Feed 1")
        let feed2 = TestFixtures.makePersistentFeed(id: UUID(), title: "Feed 2")
        mockPersistence.feeds = [feed1, feed2]

        let a1 = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        a1.feed = feed1
        let a2 = TestFixtures.makePersistentArticle(articleID: "a2", isRead: false)
        a2.feed = feed1
        let a3 = TestFixtures.makePersistentArticle(articleID: "a3", isRead: true)
        a3.feed = feed2
        let a4 = TestFixtures.makePersistentArticle(articleID: "a4", isRead: false)
        a4.feed = feed2

        mockPersistence.articlesByFeedID[feed1.id] = [a1, a2]
        mockPersistence.articlesByFeedID[feed2.id] = [a3, a4]
        mockPersistence.memberships = [
            PersistentFeedGroupMembership(feed: feed1, group: group),
            PersistentFeedGroupMembership(feed: feed2, group: group),
        ]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadGroups()

        #expect(viewModel.groupUnreadCounts[group.id] == 3)
    }
}
