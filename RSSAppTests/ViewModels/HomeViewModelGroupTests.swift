import Testing
import Foundation
@testable import RSSApp

@Suite("HomeViewModel Group Tests")
struct HomeViewModelGroupTests {

    // MARK: - Load Groups

    @Test("loadGroups populates groups array")
    @MainActor
    func loadGroupsSuccess() {
        let mock = MockFeedPersistenceService()
        let g1 = TestFixtures.makePersistentFeedGroup(name: "Tech", sortOrder: 0)
        let g2 = TestFixtures.makePersistentFeedGroup(name: "News", sortOrder: 1)
        mock.groups = [g2, g1]  // out of order to verify sorting

        let vm = HomeViewModel(persistence: mock)
        vm.loadGroups()

        #expect(vm.groups.count == 2)
        #expect(vm.groups[0].name == "Tech")
        #expect(vm.groups[1].name == "News")
    }

    @Test("loadGroups sets errorMessage on failure")
    @MainActor
    func loadGroupsError() {
        let mock = MockFeedPersistenceService()
        mock.groupError = NSError(domain: "test", code: 1)

        let vm = HomeViewModel(persistence: mock)
        vm.loadGroups()

        #expect(vm.groups.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - Group Unread Counts

    @Test("loadGroupUnreadCounts computes per-group counts")
    @MainActor
    func loadGroupUnreadCounts() {
        let mock = MockFeedPersistenceService()
        let group = TestFixtures.makePersistentFeedGroup(name: "Tech")
        mock.groups = [group]

        let feed = TestFixtures.makePersistentFeed()
        feed.group = group
        mock.feeds = [feed]

        let unread = TestFixtures.makePersistentArticle(articleID: "u1", isRead: false)
        unread.feed = feed
        let read = TestFixtures.makePersistentArticle(articleID: "r1", isRead: true)
        read.feed = feed
        mock.articlesByFeedID[feed.id] = [unread, read]

        let vm = HomeViewModel(persistence: mock)
        vm.loadGroups()
        vm.loadGroupUnreadCounts()

        #expect(vm.groupUnreadCounts[group.id] == 1)
    }

    // MARK: - CRUD

    @Test("addGroup creates group and reloads list")
    @MainActor
    func addGroupSuccess() {
        let mock = MockFeedPersistenceService()
        let vm = HomeViewModel(persistence: mock)

        vm.addGroup(name: "Tech")

        #expect(vm.groups.count == 1)
        #expect(vm.groups.first?.name == "Tech")
        #expect(vm.errorMessage == nil)
    }

    @Test("addGroup sets sortOrder to next available value")
    @MainActor
    func addGroupSortOrder() {
        let mock = MockFeedPersistenceService()
        let existing = TestFixtures.makePersistentFeedGroup(name: "First", sortOrder: 0)
        mock.groups = [existing]

        let vm = HomeViewModel(persistence: mock)
        vm.loadGroups()
        vm.addGroup(name: "Second")

        let second = vm.groups.first(where: { $0.name == "Second" })
        #expect(second?.sortOrder == 1)
    }

    @Test("renameGroup updates name and reloads")
    @MainActor
    func renameGroupSuccess() {
        let mock = MockFeedPersistenceService()
        let group = TestFixtures.makePersistentFeedGroup(name: "Old Name")
        mock.groups = [group]

        let vm = HomeViewModel(persistence: mock)
        vm.loadGroups()
        vm.renameGroup(group, to: "New Name")

        #expect(group.name == "New Name")
        #expect(vm.errorMessage == nil)
    }

    @Test("deleteGroup removes group and ungrouped feeds remain")
    @MainActor
    func deleteGroupSuccess() {
        let mock = MockFeedPersistenceService()
        let group = TestFixtures.makePersistentFeedGroup(name: "To Delete")
        let feed = TestFixtures.makePersistentFeed()
        feed.group = group
        mock.groups = [group]
        mock.feeds = [feed]

        let vm = HomeViewModel(persistence: mock)
        vm.loadGroups()
        vm.deleteGroup(group)

        #expect(vm.groups.isEmpty)
        // Feed should still exist but be ungrouped
        #expect(mock.feeds.count == 1)
        #expect(feed.group == nil)
    }

    @Test("moveGroup reorders groups")
    @MainActor
    func moveGroupSuccess() {
        let mock = MockFeedPersistenceService()
        let g1 = TestFixtures.makePersistentFeedGroup(name: "A", sortOrder: 0)
        let g2 = TestFixtures.makePersistentFeedGroup(name: "B", sortOrder: 1)
        let g3 = TestFixtures.makePersistentFeedGroup(name: "C", sortOrder: 2)
        mock.groups = [g1, g2, g3]

        let vm = HomeViewModel(persistence: mock)
        vm.loadGroups()

        // Move "C" (index 2) to position 0
        vm.moveGroup(from: IndexSet(integer: 2), to: 0)

        #expect(vm.groups[0].name == "C")
        #expect(vm.groups[1].name == "A")
        #expect(vm.groups[2].name == "B")
        #expect(g3.sortOrder == 0)
        #expect(g1.sortOrder == 1)
        #expect(g2.sortOrder == 2)
    }

    @Test("addGroup sets errorMessage on persistence failure")
    @MainActor
    func addGroupError() {
        let mock = MockFeedPersistenceService()
        mock.groupError = NSError(domain: "test", code: 1)

        let vm = HomeViewModel(persistence: mock)
        vm.addGroup(name: "Will Fail")

        #expect(vm.groups.isEmpty)
        #expect(vm.errorMessage != nil)
    }
}
