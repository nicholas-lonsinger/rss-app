import Foundation
import os

@MainActor
@Observable
final class EditGroupViewModel {

    private static let logger = Logger(category: "EditGroupViewModel")

    let group: PersistentFeedGroup
    var name: String
    private(set) var allFeeds: [PersistentFeed] = []
    private(set) var memberFeedIDs: Set<UUID> = []
    private(set) var errorMessage: String?

    private let persistence: FeedPersisting
    private let originalName: String

    init(group: PersistentFeedGroup, persistence: FeedPersisting) {
        self.group = group
        self.name = group.name
        self.originalName = group.name
        self.persistence = persistence
    }

    func loadFeeds() {
        do {
            allFeeds = try persistence.allFeeds()
            let groupFeeds = try persistence.feeds(in: group)
            memberFeedIDs = Set(groupFeeds.map(\.id))
            Self.logger.debug("Loaded \(self.allFeeds.count, privacy: .public) feeds, \(self.memberFeedIDs.count, privacy: .public) in group '\(self.group.name, privacy: .public)'")
        } catch {
            errorMessage = "Unable to load feeds."
            Self.logger.error("Failed to load feeds for group edit: \(error, privacy: .public)")
        }
    }

    func toggleMembership(for feed: PersistentFeed) {
        do {
            if memberFeedIDs.contains(feed.id) {
                try persistence.removeFeed(feed, from: group)
                memberFeedIDs.remove(feed.id)
                Self.logger.notice("Removed feed '\(feed.title, privacy: .public)' from group '\(self.group.name, privacy: .public)'")
            } else {
                try persistence.addFeed(feed, to: group)
                memberFeedIDs.insert(feed.id)
                Self.logger.notice("Added feed '\(feed.title, privacy: .public)' to group '\(self.group.name, privacy: .public)'")
            }
        } catch {
            errorMessage = "Unable to update group membership."
            Self.logger.error("Failed to toggle membership for feed '\(feed.title, privacy: .public)': \(error, privacy: .public)")
        }
    }

    func saveNameIfChanged() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != originalName else { return }
        do {
            try persistence.renameGroup(group, to: trimmed)
            Self.logger.notice("Renamed group from '\(self.originalName, privacy: .public)' to '\(trimmed, privacy: .public)'")
        } catch {
            errorMessage = "Unable to rename group."
            Self.logger.error("Failed to rename group: \(error, privacy: .public)")
        }
    }
}
