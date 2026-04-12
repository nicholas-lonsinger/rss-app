import Testing
import Foundation
@testable import RSSApp

@Suite("OPMLImportResult.importSummary Tests")
struct OPMLImportResultTests {

    // MARK: - Special-case messages

    @Test("All duplicates returns singular short message")
    func allDuplicatesSingular() {
        let result = OPMLImportResult(addedCount: 0, skippedCount: 1)
        #expect(result.importSummary == "All 1 feed was already in your list.")
    }

    @Test("All duplicates returns plural short message")
    func allDuplicatesPlural() {
        let result = OPMLImportResult(addedCount: 0, skippedCount: 5)
        #expect(result.importSummary == "All 5 feeds were already in your list.")
    }

    @Test("Empty file returns no-feeds message")
    func emptyFile() {
        let result = OPMLImportResult(addedCount: 0, skippedCount: 0)
        #expect(result.importSummary == "No feeds were found in the file.")
    }

    // MARK: - Feeds-only (no groups)

    @Test("Added-only shows header and feed count")
    func addedOnly() {
        let result = OPMLImportResult(addedCount: 3, skippedCount: 0)
        let summary = result.importSummary
        #expect(summary.hasPrefix("Imported from OPML:"))
        #expect(summary.contains("3 new feeds added"))
        #expect(!summary.contains("duplicate"))
        #expect(!summary.contains("group"))
    }

    @Test("Added singular uses 'feed' not 'feeds'")
    func addedSingular() {
        let result = OPMLImportResult(addedCount: 1, skippedCount: 0)
        #expect(result.importSummary.contains("1 new feed added"))
    }

    @Test("Added and skipped shows both lines")
    func addedAndSkipped() {
        let result = OPMLImportResult(addedCount: 4, skippedCount: 2)
        let summary = result.importSummary
        #expect(summary.contains("4 new feeds added"))
        #expect(summary.contains("2 duplicates skipped"))
    }

    @Test("Skipped singular uses 'duplicate' not 'duplicates'")
    func skippedSingular() {
        let result = OPMLImportResult(addedCount: 2, skippedCount: 1)
        #expect(result.importSummary.contains("1 duplicate skipped"))
    }

    // MARK: - parseSkippedCount wording

    @Test("Singular parse-skipped uses 'entry' and 'was'")
    func parseSkippedSingular() {
        let result = OPMLImportResult(addedCount: 2, skippedCount: 0, parseSkippedCount: 1)
        let summary = result.importSummary
        #expect(summary.contains("1 entry"))
        #expect(summary.contains("was skipped"))
    }

    @Test("Plural parse-skipped uses 'entries' and 'were'")
    func parseSkippedPlural() {
        let result = OPMLImportResult(addedCount: 0, skippedCount: 0, parseSkippedCount: 3)
        let summary = result.importSummary
        #expect(summary.hasPrefix("Imported from OPML:"))
        #expect(summary.contains("3 entries"))
        #expect(summary.contains("were skipped"))
    }

    @Test("All-duplicates fast path does not fire when parseSkippedCount > 0")
    func allDuplicatesFastPathBlockedByParseSkip() {
        // addedCount == 0, skippedCount > 0, parseSkippedCount == 1
        // The all-duplicates guard must not trigger; summary must describe the parse-skip.
        let result = OPMLImportResult(addedCount: 0, skippedCount: 2, parseSkippedCount: 1)
        let summary = result.importSummary
        #expect(!summary.hasPrefix("All"))
        #expect(summary.hasPrefix("Imported from OPML:"))
        #expect(summary.contains("invalid feed URL"))
        #expect(summary.contains("1 entry"))
        #expect(summary.contains("was skipped"))
    }

    // MARK: - Group counts

    @Test("New groups created line appears with correct count")
    func newGroupsCreated() {
        let result = OPMLImportResult(addedCount: 5, skippedCount: 0, groupsCreatedCount: 2)
        let summary = result.importSummary
        #expect(summary.contains("2 new groups created"))
        #expect(!summary.contains("reused"))
    }

    @Test("Existing groups reused line appears with correct count")
    func groupsReused() {
        let result = OPMLImportResult(addedCount: 3, skippedCount: 0, groupsReusedCount: 1)
        let summary = result.importSummary
        #expect(summary.contains("1 existing group reused"))
        #expect(!summary.contains("created"))
    }

    @Test("Both created and reused groups appear on same bullet")
    func groupsCreatedAndReused() {
        let result = OPMLImportResult(addedCount: 5, skippedCount: 1, groupsCreatedCount: 2, groupsReusedCount: 1)
        let summary = result.importSummary
        #expect(summary.contains("2 new groups created, 1 existing group reused"))
    }

    @Test("Groups singular uses 'group' not 'groups'")
    func groupsSingular() {
        let result = OPMLImportResult(addedCount: 1, skippedCount: 0, groupsCreatedCount: 1, groupsReusedCount: 1)
        let summary = result.importSummary
        #expect(summary.contains("1 new group created"))
        #expect(summary.contains("1 existing group reused"))
    }

    // MARK: - Error lines

    @Test("Failed feeds shows actionable message")
    func failedFeeds() {
        let result = OPMLImportResult(addedCount: 3, skippedCount: 0, failedCount: 2)
        let summary = result.importSummary
        #expect(summary.contains("2 feeds couldn't be saved"))
        #expect(summary.contains("try re-importing"))
    }

    @Test("Failed feeds singular uses 'feed' not 'feeds'")
    func failedFeedsSingular() {
        let result = OPMLImportResult(addedCount: 2, skippedCount: 0, failedCount: 1)
        #expect(result.importSummary.contains("1 feed couldn't be saved"))
    }

    @Test("Failed group assignments shows actionable message")
    func failedGroupAssignments() {
        let result = OPMLImportResult(addedCount: 2, skippedCount: 0, groupsFailedCount: 1)
        let summary = result.importSummary
        #expect(summary.contains("1 group assignment failed"))
        #expect(summary.contains("Settings logs"))
    }

    @Test("Failed group assignments plural uses 'assignments'")
    func failedGroupAssignmentsPlural() {
        let result = OPMLImportResult(addedCount: 1, skippedCount: 0, groupsFailedCount: 3)
        #expect(result.importSummary.contains("3 group assignments failed"))
    }

    // MARK: - Realistic combinations

    @Test("Full result shows all sections in order")
    func fullResult() {
        let result = OPMLImportResult(
            addedCount: 5,
            skippedCount: 2,
            failedCount: 1,
            groupsCreatedCount: 2,
            groupsReusedCount: 1,
            groupsFailedCount: 1
        )
        let lines = result.importSummary.components(separatedBy: "\n")
        #expect(lines.count == 6)
        #expect(lines[0] == "Imported from OPML:")
        #expect(lines[1].contains("5 new feeds added"))
        #expect(lines[2].contains("2 duplicates skipped"))
        #expect(lines[3].contains("2 new groups created, 1 existing group reused"))
        #expect(lines[4].contains("1 feed couldn't be saved"))
        #expect(lines[5].contains("1 group assignment failed"))
    }

    @Test("All-duplicates special case is not triggered when group failures also present")
    func allDuplicatesWithGroupFailureNotSpecialCased() {
        let result = OPMLImportResult(addedCount: 0, skippedCount: 3, groupsFailedCount: 1)
        let summary = result.importSummary
        #expect(summary.hasPrefix("Imported from OPML:"))
        #expect(summary.contains("3 duplicates skipped"))
        #expect(summary.contains("group assignment failed"))
    }

    @Test("All-duplicates special case is not triggered when feed failures also present")
    func allDuplicatesWithFeedFailureNotSpecialCased() {
        let result = OPMLImportResult(addedCount: 0, skippedCount: 3, failedCount: 1)
        let summary = result.importSummary
        #expect(summary.hasPrefix("Imported from OPML:"))
        #expect(summary.contains("3 duplicates skipped"))
        #expect(summary.contains("feed couldn't be saved"))
    }

    @Test("All-duplicates special case is not triggered when groups were created")
    func allDuplicatesWithGroupCreationNotSpecialCased() {
        let result = OPMLImportResult(addedCount: 0, skippedCount: 2, groupsCreatedCount: 1)
        let summary = result.importSummary
        #expect(summary.hasPrefix("Imported from OPML:"))
        #expect(summary.contains("2 duplicates skipped"))
        #expect(summary.contains("group"))
    }
}
