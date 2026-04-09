import Foundation
import SwiftData

@Model
final class PersistentFeedGroup {

    // MARK: - Identity

    var id: UUID

    // MARK: - Metadata

    var name: String
    var createdDate: Date

    /// Explicit ordering for manual reordering on the Home screen.
    /// Groups are displayed in ascending `sortOrder`.
    var sortOrder: Int

    // MARK: - Relationships

    /// Feeds belonging to this group. Deleting a group nullifies this
    /// relationship — feeds become ungrouped, not deleted.
    @Relationship(deleteRule: .nullify, inverse: \PersistentFeed.group)
    var feeds: [PersistentFeed]

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
        self.feeds = []
    }
}
