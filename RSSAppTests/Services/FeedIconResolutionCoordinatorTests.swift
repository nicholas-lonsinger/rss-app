import Testing
import Foundation
@testable import RSSApp

@Suite("FeedIconResolutionCoordinator Tests")
struct FeedIconResolutionCoordinatorTests {

    // MARK: - Helpers

    /// Thread-safe counter used to verify how many times the work closure was invoked.
    private actor CallCounter {
        private(set) var count = 0

        func increment() {
            count += 1
        }
    }

    // MARK: - Tests

    @Test("Concurrent calls for the same feedID coalesce to a single work invocation")
    func concurrentCallsForSameFeedIDCoalesce() async throws {
        let coordinator = FeedIconResolutionCoordinator()
        let counter = CallCounter()
        let feedID = UUID()
        let expectedURL = URL(string: "https://example.com/icon.png")!
        let expectedStyle = FeedIconBackgroundStyle.light

        // Launch 5 tasks simultaneously for the same feedID.
        // The work closure delays 50ms so all callers are guaranteed to arrive
        // before the first task completes, ensuring coalescing is exercised.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    let result = try await coordinator.coalesce(feedID: feedID) {
                        await counter.increment()
                        try? await Task.sleep(for: .milliseconds(50))
                        return (url: expectedURL, backgroundStyle: expectedStyle)
                    }
                    #expect(result?.url == expectedURL)
                    #expect(result?.backgroundStyle == expectedStyle)
                }
            }
        }

        let invokeCount = await counter.count
        #expect(invokeCount == 1, "Work closure should run exactly once for coalesced calls; ran \(invokeCount) times")
    }

    @Test("Concurrent calls for different feedIDs proceed independently")
    func concurrentCallsForDifferentFeedIDsProceedIndependently() async throws {
        let coordinator = FeedIconResolutionCoordinator()
        let counter = CallCounter()
        let feedIDs = [UUID(), UUID(), UUID()]

        try await withThrowingTaskGroup(of: Void.self) { group in
            for feedID in feedIDs {
                group.addTask {
                    _ = try await coordinator.coalesce(feedID: feedID) {
                        await counter.increment()
                        return nil
                    }
                }
            }
        }

        let invokeCount = await counter.count
        #expect(invokeCount == feedIDs.count, "Work closure should run once per distinct feedID; ran \(invokeCount) times for \(feedIDs.count) feeds")
    }

    /// Single-shot async gate: the sender calls `signal()` once; the receiver
    /// calls `wait()` and suspends until the signal arrives.
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var signalled = false

        func signal() {
            if let c = continuation {
                c.resume()
                continuation = nil
            } else {
                signalled = true
            }
        }

        func wait() async {
            if signalled { return }
            await withCheckedContinuation { continuation = $0 }
        }
    }

    @Test("Cancelling one awaiter does not cancel the shared task or other awaiters")
    func cancellingOneAwaiterDoesNotCancelSharedTask() async throws {
        let coordinator = FeedIconResolutionCoordinator()
        let counter = CallCounter()
        let feedID = UUID()
        let expectedURL = URL(string: "https://example.com/icon.png")!
        let expectedStyle = FeedIconBackgroundStyle.light

        // Gate that lets the test cancel task B only after the work closure has started.
        let gate = Gate()

        // Task A: first caller — owns the work closure. Signals the gate when it
        // starts so we can cancel task B while the work is still in progress.
        // `try` (not `try?`) so an unexpected throw fails the test loudly.
        let taskA = Task {
            try await coordinator.coalesce(feedID: feedID) {
                await counter.increment()
                await gate.signal()
                try? await Task.sleep(for: .milliseconds(100))
                return (url: expectedURL, backgroundStyle: expectedStyle)
            }
        }

        // Wait until the work closure is running before launching and cancelling task B.
        await gate.wait()

        // Task B: concurrent caller that arrives while the work is in progress.
        // It awaits the shared task; cancelling it must not cancel the coordinator's
        // unstructured Task, which is not a child of task B.
        let taskB = Task {
            try? await coordinator.coalesce(feedID: feedID) {
                // This closure must never run — task B awaits task A's result.
                await counter.increment()
                return nil
            }
        }
        taskB.cancel()

        // Task C: another concurrent caller that must still receive the correct result.
        // `try` (not `try?`) so an unexpected throw fails the test loudly.
        let taskC = Task {
            try await coordinator.coalesce(feedID: feedID) {
                await counter.increment()
                return nil
            }
        }

        let resultA = try await taskA.value
        _ = await taskB.value
        let resultC = try await taskC.value

        let invokeCount = await counter.count
        #expect(invokeCount == 1, "Work closure should run exactly once; ran \(invokeCount) times")
        #expect(resultA?.url == expectedURL, "Task A should receive the resolved URL")
        #expect(resultC?.url == expectedURL, "Task C should receive the resolved URL despite task B being cancelled")
    }

    @Test("CancellationError from work propagates to all coalesced awaiters via Result")
    func cancellationErrorPropagatesFromWorkToAllAwaiters() async {
        let coordinator = FeedIconResolutionCoordinator()
        let feedID = UUID()

        // Gate ensures tasks B and C are coalesced on the same in-flight task
        // before work completes and throws CancellationError.
        let gate = Gate()

        // Thread-safe store recording whether each task received CancellationError.
        actor OutcomeStore {
            private(set) var results: [Int: Bool] = [:]
            func record(index: Int, threw: Bool) { results[index] = threw }
        }
        let outcomes = OutcomeStore()

        // WorkProvider exposes the typed-throwing work as an actor method. The explicit
        // closure signature on the `coalesce` call site below (`() async throws(CancellationError) ->`)
        // is required because Swift cannot infer `throws(CancellationError)` for an
        // `@Sendable` closure that calls an actor method — it widens to `any Error`.
        actor WorkProvider {
            let gate: Gate
            init(gate: Gate) { self.gate = gate }

            func cancellingWork() async throws(CancellationError) -> (url: URL, backgroundStyle: FeedIconBackgroundStyle)? {
                await gate.signal()
                // Pause so tasks B and C arrive and coalesce before work throws.
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { cont.resume() }
                }
                throw CancellationError()
            }
        }
        let provider = WorkProvider(gate: gate)

        // Three tasks coalesce on the same feedID. The work (owned by task A) throws
        // CancellationError; all three callers must propagate that error — not return nil,
        // which would incorrectly trigger backoff for a genuine resolution miss.
        let taskA = Task<Void, Never> {
            do {
                _ = try await coordinator.coalesce(feedID: feedID) { () async throws(CancellationError) -> (url: URL, backgroundStyle: FeedIconBackgroundStyle)? in
                    try await provider.cancellingWork()
                }
                await outcomes.record(index: 0, threw: false)
            } catch {
                await outcomes.record(index: 0, threw: error is CancellationError)
            }
        }

        await gate.wait()

        let taskB = Task<Void, Never> {
            do {
                _ = try await coordinator.coalesce(feedID: feedID) { nil }
                await outcomes.record(index: 1, threw: false)
            } catch {
                await outcomes.record(index: 1, threw: error is CancellationError)
            }
        }

        let taskC = Task<Void, Never> {
            do {
                _ = try await coordinator.coalesce(feedID: feedID) { nil }
                await outcomes.record(index: 2, threw: false)
            } catch {
                await outcomes.record(index: 2, threw: error is CancellationError)
            }
        }

        _ = await taskA.value
        _ = await taskB.value
        _ = await taskC.value

        let results = await outcomes.results
        #expect(results[0] == true, "Task A (work owner) should receive CancellationError")
        #expect(results[1] == true, "Task B (coalesced awaiter) should receive CancellationError, not nil")
        #expect(results[2] == true, "Task C (coalesced awaiter) should receive CancellationError, not nil")
    }

    @Test("Completed entry is removed, allowing a fresh resolution on the next call")
    func completedEntryRemovedAllowsFreshResolution() async throws {
        let coordinator = FeedIconResolutionCoordinator()
        let counter = CallCounter()
        let feedID = UUID()

        // First call — completes normally.
        _ = try await coordinator.coalesce(feedID: feedID) {
            await counter.increment()
            return nil
        }

        // Second call — must start fresh because the first entry was removed on completion.
        _ = try await coordinator.coalesce(feedID: feedID) {
            await counter.increment()
            return nil
        }

        let invokeCount = await counter.count
        #expect(invokeCount == 2, "Work closure should run again after the first resolution completed; ran \(invokeCount) times")
    }
}
