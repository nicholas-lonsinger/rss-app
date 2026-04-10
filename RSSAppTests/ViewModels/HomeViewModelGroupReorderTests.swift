import Testing
import Foundation
@testable import RSSApp

@Suite("HomeViewModel Group Reorder Tests")
struct HomeViewModelGroupReorderTests {

    @Test("moveGroup reorders groups and persists sortOrder")
    @MainActor
    func moveGroupSuccess() {
        let mockPersistence = MockFeedPersistenceService()
        let groupA = PersistentFeedGroup(name: "Alpha", sortOrder: 0)
        let groupB = PersistentFeedGroup(name: "Beta", sortOrder: 1)
        let groupC = PersistentFeedGroup(name: "Charlie", sortOrder: 2)
        mockPersistence.groups = [groupA, groupB, groupC]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadGroups()
        #expect(viewModel.groups.map(\.name) == ["Alpha", "Beta", "Charlie"])

        // Move Charlie (index 2) to index 0
        viewModel.moveGroup(from: IndexSet(integer: 2), to: 0)

        #expect(viewModel.groups.map(\.name) == ["Charlie", "Alpha", "Beta"])
        #expect(viewModel.groups[0].sortOrder == 0)
        #expect(viewModel.groups[1].sortOrder == 1)
        #expect(viewModel.groups[2].sortOrder == 2)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("moveGroup restores order on persistence failure")
    @MainActor
    func moveGroupError() {
        let mockPersistence = MockFeedPersistenceService()
        let groupA = PersistentFeedGroup(name: "Alpha", sortOrder: 0)
        let groupB = PersistentFeedGroup(name: "Beta", sortOrder: 1)
        mockPersistence.groups = [groupA, groupB]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadGroups()

        // Inject error for the updateGroupOrder call
        mockPersistence.updateGroupOrderError = NSError(domain: "test", code: 1)

        viewModel.moveGroup(from: IndexSet(integer: 1), to: 0)

        // On failure, loadGroups() reloads from persistence, restoring the original order
        #expect(viewModel.groups.map(\.name) == ["Alpha", "Beta"])
        #expect(viewModel.errorMessage != nil)
    }

    @Test("moveGroup moves last group to middle position")
    @MainActor
    func moveGroupToMiddle() {
        let mockPersistence = MockFeedPersistenceService()
        let groupA = PersistentFeedGroup(name: "Alpha", sortOrder: 0)
        let groupB = PersistentFeedGroup(name: "Beta", sortOrder: 1)
        let groupC = PersistentFeedGroup(name: "Charlie", sortOrder: 2)
        mockPersistence.groups = [groupA, groupB, groupC]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadGroups()

        // Move Alpha (index 0) to after Beta (destination 2 means "before index 2")
        viewModel.moveGroup(from: IndexSet(integer: 0), to: 2)

        #expect(viewModel.groups.map(\.name) == ["Beta", "Alpha", "Charlie"])
        #expect(viewModel.groups[0].sortOrder == 0)
        #expect(viewModel.groups[1].sortOrder == 1)
        #expect(viewModel.groups[2].sortOrder == 2)
    }
}
