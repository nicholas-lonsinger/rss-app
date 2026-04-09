import BackgroundTasks
import Foundation
import os

/// Bridges `BGTaskScheduler` launch handlers (delivered on a background queue)
/// into `FeedRefreshService` (main-actor isolated). Owns the contract with
/// `BGTask`: cancellation propagation via `expirationHandler`, single
/// `setTaskCompleted(success:)` call on all paths, and rescheduling of the
/// next window after every completed run.
final class BackgroundRefreshCoordinator: Sendable {

    private static let logger = Logger(category: "BackgroundRefreshCoordinator")

    private let refreshService: FeedRefreshService

    init(refreshService: FeedRefreshService) {
        self.refreshService = refreshService
    }

    /// Called from `BGTaskScheduler`'s launch handler when either refresh task
    /// fires. Wraps the refresh in a `Task { @MainActor }` (BGTask is delivered
    /// on a background queue; the refresh service is main-actor isolated),
    /// wires up `expirationHandler` to cancel the work task, and guarantees
    /// `setTaskCompleted(success:)` is called exactly once with a value that
    /// reflects the actual refresh outcome (not just cancellation).
    func handle(_ task: BGTask) {
        Self.logger.notice("BGTask launched: \(task.description, privacy: .public)")

        // Always queue up the next run first, even if this one throws or is
        // cancelled, so a single refresh failure does not stall the background
        // schedule. Called synchronously (no Task hop) because
        // `scheduleNextRefresh` is a non-isolated static method that only
        // touches thread-safe APIs (UserDefaults, BGTaskScheduler.shared).
        // A `submit` failure at this site is logged and swallowed — the user
        // already saw whatever settings change triggered this path; there is
        // no UI context to surface an alert here.
        do {
            try BackgroundRefreshScheduler.scheduleNextRefresh()
        } catch {
            Self.logger.error("Failed to reschedule next background refresh: \(error, privacy: .public)")
        }

        // RATIONALE: BGTask is a framework class that is not formally Sendable
        // in Swift 6, but Apple's BackgroundTasks API documents `setTaskCompleted`
        // and `expirationHandler` as safe to call from any thread. Wrapping in a
        // CompletionGate captures `task` once, guards completion with an NSLock,
        // and exposes a Sendable interface so both the main-actor work task and
        // the background-queue expiration handler can signal completion safely.
        let gate = CompletionGate(task: task)

        // RATIONALE: The work task must be created *before* `expirationHandler`
        // is assigned because the handler captures `workTask` by reference. In
        // the brief window between `workTask` creation and `expirationHandler`
        // assignment, an expiration firing would not cancel the work task and
        // the task would run to natural completion (still reporting a correct
        // outcome via the gate). Making the window smaller is structurally
        // impossible — there is no BackgroundTasks API for installing the
        // expiration handler before the work begins — so this ordering is the
        // canonical pattern.
        let workTask = Task { @MainActor in
            let outcome = await self.refreshService.refreshAllFeeds()
            // Drain any in-flight thumbnail prefetch and icon resolution tasks
            // before reporting success, so the allotted background runtime is
            // actually used for them rather than cancelled when the OS
            // reclaims the process.
            await self.refreshService.awaitPendingWork()
            Self.logger.notice("BGTask refresh outcome: \(String(describing: outcome), privacy: .public)")
            gate.completeOnce(success: Self.isSuccess(outcome: outcome))
        }

        task.expirationHandler = { [gate] in
            Self.logger.warning("BGTask expirationHandler fired — cancelling work and marking failed")
            workTask.cancel()
            gate.completeOnce(success: false)
        }
    }

    /// Maps a `FeedRefreshService.Outcome` to the success/failure signal that
    /// `BGTaskScheduler` uses to tune future scheduling frequency.
    ///
    /// A reported "success" tells iOS to keep scheduling this task at its
    /// configured cadence; "failure" causes iOS to back off. The mapping must
    /// therefore be honest: a refresh that saved nothing, or that had every
    /// feed fail, must not be reported as success — otherwise iOS keeps
    /// firing a broken feature at full cadence while the user sees no new
    /// articles and has no visible error path.
    ///
    /// - `.skipped` is reported as success: there was genuinely no work to do
    ///   (no feeds, or another caller held the refresh), which is not a failure
    ///   condition for the schedule.
    /// - `.setupFailed` → failure: we could not read the feed list.
    /// - `.cancelled` → failure: the BG window was not fully used.
    /// - `.completed(Summary)` → success only when the save persisted cleanly
    ///   and no feed fetches failed. Partial success (some feeds refreshed,
    ///   some failed) is reported as failure so iOS backs off — the next
    ///   refresh will retry and, if the issue is transient, rapidly recover.
    static func isSuccess(outcome: FeedRefreshService.Outcome) -> Bool {
        switch outcome {
        case .skipped:
            return true
        case .setupFailed, .cancelled:
            return false
        case .completed(let summary):
            return !summary.saveDidFail && summary.failureCount == 0
        }
    }
}

/// Ensures `BGTask.setTaskCompleted(success:)` is called at most once across
/// the main-actor work task and the background-queue `expirationHandler`.
/// BGTask itself is not Sendable, so this gate owns the only reference to it
/// after construction and gates `setTaskCompleted(success:)` behind `lock`.
private final class CompletionGate: @unchecked Sendable {

    private static let logger = Logger(category: "BackgroundRefreshCoordinator.CompletionGate")

    private let lock = NSLock()
    private var completed = false
    // RATIONALE: `@unchecked Sendable` is correct here because the only access
    // to `task` after `init` is through `completeOnce`, which serializes on
    // `lock`. `init` assigns `task` without the lock because construction is
    // single-threaded — the gate is created inside `handle(_:)` before any
    // task captures the reference. BGTask's `setTaskCompleted(success:)` is
    // documented as callable from any thread.
    private let task: BGTask

    init(task: BGTask) {
        self.task = task
    }

    func completeOnce(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        completed = true
        task.setTaskCompleted(success: success)
        Self.logger.notice("BGTask setTaskCompleted(success: \(success, privacy: .public))")
    }
}
