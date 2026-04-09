import Testing
@testable import RSSApp

/// Matrix tests for `BackgroundRefreshCoordinator.isSuccess(outcome:)`.
///
/// This is the policy gate that decides whether `BGTaskScheduler` should
/// treat a completed run as a success or a failure. A mistake here trains
/// iOS to keep firing a broken feature at full cadence, so the mapping
/// rule is load-bearing. The tests below pin every branch of the mapping
/// in the same style as `BackgroundRefreshSchedulerTests.decideTaskType`.
///
/// Rule (matches the doc comment on `isSuccess(outcome:)`):
/// - `.skipped` → `true` (no work to do is not a failure condition)
/// - `.setupFailed` → `false` (we could not even begin)
/// - `.cancelled` → `false` (the BG window was not fully used)
/// - `.completed(Summary)` → `!saveDidFail && failureCount == 0`
///   Partial success (some feeds refreshed, some failed) is reported as
///   failure so iOS backs off; `retentionCleanupFailed` is intentionally
///   NOT considered a failure (cosmetic, next refresh retries cleanup).
@Suite("BackgroundRefreshCoordinator isSuccess Tests")
struct BackgroundRefreshCoordinatorTests {

    // MARK: - Terminal outcomes

    @Test(".skipped reports success (no work to do is not a failure)")
    func skippedIsSuccess() {
        #expect(BackgroundRefreshCoordinator.isSuccess(outcome: .skipped) == true)
    }

    @Test(".setupFailed reports failure")
    func setupFailedIsFailure() {
        #expect(BackgroundRefreshCoordinator.isSuccess(outcome: .setupFailed) == false)
    }

    @Test(".cancelled reports failure")
    func cancelledIsFailure() {
        #expect(BackgroundRefreshCoordinator.isSuccess(outcome: .cancelled(totalFeeds: 5)) == false)
    }

    // MARK: - .completed branches

    @Test(".completed with clean summary reports success")
    func completedCleanIsSuccess() {
        let summary = FeedRefreshService.Outcome.Summary(
            totalFeeds: 3,
            failureCount: 0,
            saveDidFail: false,
            retentionCleanupFailed: false
        )
        #expect(BackgroundRefreshCoordinator.isSuccess(outcome: .completed(summary)) == true)
    }

    @Test(".completed with saveDidFail reports failure")
    func completedSaveDidFailIsFailure() {
        let summary = FeedRefreshService.Outcome.Summary(
            totalFeeds: 3,
            failureCount: 0,
            saveDidFail: true,
            retentionCleanupFailed: false
        )
        #expect(BackgroundRefreshCoordinator.isSuccess(outcome: .completed(summary)) == false)
    }

    @Test(".completed with any failureCount > 0 reports failure")
    func completedPartialFailureIsFailure() {
        // Even 1 of 3 failing should back off scheduling — we don't want
        // iOS to keep firing a refresh where some feeds are consistently
        // unreachable.
        let summary = FeedRefreshService.Outcome.Summary(
            totalFeeds: 3,
            failureCount: 1,
            saveDidFail: false,
            retentionCleanupFailed: false
        )
        #expect(BackgroundRefreshCoordinator.isSuccess(outcome: .completed(summary)) == false)
    }

    @Test(".completed with all feeds failing reports failure")
    func completedTotalFailureIsFailure() {
        let summary = FeedRefreshService.Outcome.Summary(
            totalFeeds: 3,
            failureCount: 3,
            saveDidFail: false,
            retentionCleanupFailed: false
        )
        #expect(BackgroundRefreshCoordinator.isSuccess(outcome: .completed(summary)) == false)
    }

    @Test(".completed with only retentionCleanupFailed reports success")
    func completedRetentionOnlyIsSuccess() {
        // Retention cleanup is cosmetic (self-healing on the next refresh)
        // and must NOT cause iOS to back off. This pins the deliberate
        // choice to leave retention out of the success gate.
        let summary = FeedRefreshService.Outcome.Summary(
            totalFeeds: 3,
            failureCount: 0,
            saveDidFail: false,
            retentionCleanupFailed: true
        )
        #expect(BackgroundRefreshCoordinator.isSuccess(outcome: .completed(summary)) == true)
    }
}
