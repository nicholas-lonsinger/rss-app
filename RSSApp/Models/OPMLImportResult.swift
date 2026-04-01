import Foundation

struct OPMLImportResult: Sendable, Equatable {
    let addedCount: Int
    let skippedCount: Int
    let totalInFile: Int
}
