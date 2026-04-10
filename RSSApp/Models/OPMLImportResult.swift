import Foundation

struct OPMLImportResult: Sendable, Equatable {
    let addedCount: Int
    let skippedCount: Int
    let failedCount: Int
    let groupsCreatedCount: Int
    let groupsReusedCount: Int
    let groupsFailedCount: Int
    var totalInFile: Int { addedCount + skippedCount + failedCount }

    init(
        addedCount: Int,
        skippedCount: Int,
        failedCount: Int = 0,
        groupsCreatedCount: Int = 0,
        groupsReusedCount: Int = 0,
        groupsFailedCount: Int = 0
    ) {
        self.addedCount = addedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.groupsCreatedCount = groupsCreatedCount
        self.groupsReusedCount = groupsReusedCount
        self.groupsFailedCount = groupsFailedCount
    }
}
