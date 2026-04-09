import Foundation
import SwiftData

/// Join model for the many-to-many relationship between feeds and groups.
/// A feed can belong to multiple groups; a group can contain multiple feeds.
///
/// Uniqueness of the (feed, group) pair is enforced at the application layer
/// — see `FeedPersisting.addFeed(_:to:)`.
@Model
final class PersistentFeedGroupMembership {

    // MARK: - Identity

    var id: UUID

    // MARK: - Relationships

    /// The feed in this membership. Inverse declared on `PersistentFeed.groupMemberships`.
    var feed: PersistentFeed?

    /// The group in this membership. Inverse declared on `PersistentFeedGroup.memberships`.
    var group: PersistentFeedGroup?

    init(
        id: UUID = UUID(),
        feed: PersistentFeed,
        group: PersistentFeedGroup
    ) {
        self.id = id
        self.feed = feed
        self.group = group
    }
}
