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
    /// `setTaskCompleted(success:)` is called exactly once.
    func handle(_ task: BGTask) {
        Self.logger.notice("BGTask launched: \(task.description, privacy: .public)")

        // Always queue up the next run, even if this one throws or is cancelled,
        // so a single refresh failure does not stall the background schedule.
        Task { @MainActor in
            BackgroundRefreshScheduler.scheduleNextRefresh()
        }

        // RATIONALE: BGTask is a framework class that is not formally Sendable
        // in Swift 6, but Apple's BackgroundTasks API documents `setTaskCompleted`
        // and `expirationHandler` as safe to call from any thread. Wrapping in a
        // CompletionGate captures `task` once, guards completion with an NSLock,
        // and exposes a Sendable interface so both the main-actor work task and
        // the background-queue expiration handler can signal completion safely.
        let gate = CompletionGate(task: task)

        let workTask = Task { @MainActor in
            let outcome = await self.refreshService.refreshAllFeeds()
            // Drain any in-flight thumbnail prefetch before reporting success,
            // so the allotted background runtime is actually used for it rather
            // than cancelled when the OS reclaims the process.
            await self.refreshService.awaitPendingWork()
            Self.logger.notice("BGTask refresh outcome: \(String(describing: outcome), privacy: .public)")
            gate.completeOnce(success: !Task.isCancelled)
        }

        task.expirationHandler = { [gate] in
            Self.logger.warning("BGTask expirationHandler fired — cancelling work and marking failed")
            workTask.cancel()
            gate.completeOnce(success: false)
        }
    }
}

/// Ensures `BGTask.setTaskCompleted(success:)` is called at most once across
/// the main-actor work task and the background-queue `expirationHandler`.
/// BGTask itself is not Sendable, so this gate owns the only reference to it
/// and mediates all access through a lock.
private final class CompletionGate: @unchecked Sendable {

    private static let logger = Logger(category: "BackgroundRefreshCoordinator.CompletionGate")

    private let lock = NSLock()
    private var completed = false
    // RATIONALE: `@unchecked Sendable` is correct here because the only access
    // to `task` is through `completeOnce`, which serializes on `lock`. BGTask's
    // `setTaskCompleted(success:)` is documented as callable from any thread.
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
