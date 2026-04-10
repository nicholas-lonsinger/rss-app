import Foundation
import SwiftData

@Model
final class PersistentFeedGroup {

    // MARK: - Identity

    var id: UUID
    var name: String

    // MARK: - Metadata

    var createdDate: Date

    /// Position within the groups list. Callers assign incrementing values
    /// at creation time (see `HomeViewModel.addGroup`); users can customize
    /// the order via drag-to-reorder on the Home screen (issue #333).
    var sortOrder: Int

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \PersistentFeedGroupMembership.group)
    var memberships: [PersistentFeedGroupMembership]

    init(
        id: UUID = UUID(),
        name: String,
        createdDate: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.createdDate = createdDate
        self.sortOrder = sortOrder
        self.memberships = []
    }
}
