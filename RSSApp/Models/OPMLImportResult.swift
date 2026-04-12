import Foundation

struct OPMLImportResult: Sendable, Equatable {
    let addedCount: Int
    let skippedCount: Int
    let failedCount: Int
    let parseSkippedCount: Int
    let groupsCreatedCount: Int
    let groupsReusedCount: Int
    let groupsFailedCount: Int
    var totalInFile: Int { addedCount + skippedCount + failedCount + parseSkippedCount }

    init(
        addedCount: Int,
        skippedCount: Int,
        failedCount: Int = 0,
        parseSkippedCount: Int = 0,
        groupsCreatedCount: Int = 0,
        groupsReusedCount: Int = 0,
        groupsFailedCount: Int = 0
    ) {
        self.addedCount = addedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.parseSkippedCount = parseSkippedCount
        self.groupsCreatedCount = groupsCreatedCount
        self.groupsReusedCount = groupsReusedCount
        self.groupsFailedCount = groupsFailedCount
    }

    /// A user-facing multi-line bulleted summary of the import result.
    var importSummary: String {
        if addedCount == 0 && skippedCount > 0 && failedCount == 0 && parseSkippedCount == 0
            && groupsCreatedCount == 0 && groupsReusedCount == 0 && groupsFailedCount == 0 {
            return "All \(skippedCount) \(skippedCount == 1 ? "feed was" : "feeds were") already in your list."
        }

        if totalInFile == 0 && groupsCreatedCount == 0 && groupsReusedCount == 0 && groupsFailedCount == 0 {
            return "No feeds were found in the file."
        }

        var lines: [String] = ["Imported from OPML:"]

        if addedCount > 0 {
            lines.append("• \(addedCount) new \(addedCount == 1 ? "feed" : "feeds") added")
        }
        if skippedCount > 0 {
            lines.append("• \(skippedCount) \(skippedCount == 1 ? "duplicate" : "duplicates") skipped")
        }
        if parseSkippedCount > 0 {
            lines.append(
                "• \(parseSkippedCount) \(parseSkippedCount == 1 ? "entry" : "entries") in the file had an invalid feed URL and \(parseSkippedCount == 1 ? "was" : "were") skipped"
            )
        }

        let hasGroupActivity = groupsCreatedCount > 0 || groupsReusedCount > 0
        if hasGroupActivity {
            var groupParts: [String] = []
            if groupsCreatedCount > 0 {
                groupParts.append("\(groupsCreatedCount) new \(groupsCreatedCount == 1 ? "group" : "groups") created")
            }
            if groupsReusedCount > 0 {
                groupParts.append("\(groupsReusedCount) existing \(groupsReusedCount == 1 ? "group" : "groups") reused")
            }
            lines.append("• \(groupParts.joined(separator: ", "))")
        }

        if failedCount > 0 {
            lines.append(
                "• \(failedCount) \(failedCount == 1 ? "feed" : "feeds") couldn't be saved — check the feed URL and try re-importing"
            )
        }
        if groupsFailedCount > 0 {
            lines.append(
                "• \(groupsFailedCount) group \(groupsFailedCount == 1 ? "assignment" : "assignments") failed — check Settings logs and try re-importing"
            )
        }

        return lines.joined(separator: "\n")
    }
}
