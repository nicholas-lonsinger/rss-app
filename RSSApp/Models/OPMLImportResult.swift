import Foundation

struct OPMLImportResult: Sendable, Equatable {
    let addedCount: Int
    let skippedCount: Int
    var totalInFile: Int { addedCount + skippedCount }
}
