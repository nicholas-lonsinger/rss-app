import Testing
import Foundation
@testable import RSSApp

@Suite("EditGroupViewModel Tests")
struct EditGroupViewModelTests {

    // MARK: - loadFeeds

    @Test("loadFeeds populates all feeds and identifies members")
    @MainActor
    func loadFeedsSuccess() {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Tech")
        mock.groups = [group]

        let feed1 = TestFixtures.makePersistentFeed(id: UUID(), title: "Feed 1")
        let feed2 = TestFixtures.makePersistentFeed(id: UUID(), title: "Feed 2")
        let feed3 = TestFixtures.makePersistentFeed(id: UUID(), title: "Feed 3")
        mock.feeds = [feed1, feed2, feed3]
        mock.memberships = [PersistentFeedGroupMembership(feed: feed1, group: group)]

        let viewModel = EditGroupViewModel(group: group, persistence: mock)
        viewModel.loadFeeds()

        #expect(viewModel.allFeeds.count == 3)
        #expect(viewModel.memberFeedIDs == Set([feed1.id]))
        #expect(viewModel.errorMessage == nil)
    }

    @Test("loadFeeds sets error on failure")
    @MainActor
    func loadFeedsError() {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Fail")
        mock.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = EditGroupViewModel(group: group, persistence: mock)
        viewModel.loadFeeds()

        #expect(viewModel.errorMessage != nil)
    }

    // MARK: - toggleMembership

    @Test("toggleMembership adds feed to group")
    @MainActor
    func toggleMembershipAdd() {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Tech")
        mock.groups = [group]

        let feed = TestFixtures.makePersistentFeed()
        mock.feeds = [feed]

        let viewModel = EditGroupViewModel(group: group, persistence: mock)
        viewModel.loadFeeds()
        #expect(viewModel.memberFeedIDs.isEmpty)

        viewModel.toggleMembership(for: feed)

        #expect(viewModel.memberFeedIDs.contains(feed.id))
        #expect(mock.memberships.count == 1)
    }

    @Test("toggleMembership removes feed from group")
    @MainActor
    func toggleMembershipRemove() {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Tech")
        mock.groups = [group]

        let feed = TestFixtures.makePersistentFeed()
        mock.feeds = [feed]
        mock.memberships = [PersistentFeedGroupMembership(feed: feed, group: group)]

        let viewModel = EditGroupViewModel(group: group, persistence: mock)
        viewModel.loadFeeds()
        #expect(viewModel.memberFeedIDs.contains(feed.id))

        viewModel.toggleMembership(for: feed)

        #expect(!viewModel.memberFeedIDs.contains(feed.id))
        #expect(mock.memberships.isEmpty)
    }

    @Test("toggleMembership round-trip: add then remove")
    @MainActor
    func toggleMembershipRoundTrip() {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Tech")
        let feed = TestFixtures.makePersistentFeed()
        mock.feeds = [feed]
        mock.groups = [group]

        let viewModel = EditGroupViewModel(group: group, persistence: mock)
        viewModel.loadFeeds()

        viewModel.toggleMembership(for: feed)
        #expect(viewModel.memberFeedIDs.contains(feed.id))

        viewModel.toggleMembership(for: feed)
        #expect(!viewModel.memberFeedIDs.contains(feed.id))
    }

    // MARK: - saveNameIfChanged

    @Test("saveNameIfChanged persists new name when changed")
    @MainActor
    func saveNameChanged() {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Old")
        mock.groups = [group]

        let viewModel = EditGroupViewModel(group: group, persistence: mock)
        viewModel.name = "New"
        viewModel.saveNameIfChanged()

        #expect(group.name == "New")
    }

    @Test("saveNameIfChanged is no-op when name unchanged")
    @MainActor
    func saveNameUnchanged() {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Same")
        mock.groups = [group]

        let viewModel = EditGroupViewModel(group: group, persistence: mock)
        viewModel.saveNameIfChanged()

        #expect(group.name == "Same")
    }

    @Test("saveNameIfChanged trims whitespace and rejects empty")
    @MainActor
    func saveNameEmpty() {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Keep")
        mock.groups = [group]

        let viewModel = EditGroupViewModel(group: group, persistence: mock)
        viewModel.name = "   "
        viewModel.saveNameIfChanged()

        #expect(group.name == "Keep")
    }
}
