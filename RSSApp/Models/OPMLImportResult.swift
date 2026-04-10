import Foundation

struct OPMLImportResult: Sendable, Equatable {
    let addedCount: Int
    let skippedCount: Int
    let groupsCreatedCount: Int
    let groupsReusedCount: Int
    var totalInFile: Int { addedCount + skippedCount }

    init(
        addedCount: Int,
        skippedCount: Int,
        groupsCreatedCount: Int = 0,
        groupsReusedCount: Int = 0
    ) {
        self.addedCount = addedCount
        self.skippedCount = skippedCount
        self.groupsCreatedCount = groupsCreatedCount
        self.groupsReusedCount = groupsReusedCount
    }
}
