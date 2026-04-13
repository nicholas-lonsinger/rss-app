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
    func concurrentCallsForSameFeedIDCoalesce() async {
        let coordinator = FeedIconResolutionCoordinator()
        let counter = CallCounter()
        let feedID = UUID()
        let expectedURL = URL(string: "https://example.com/icon.png")!
        let expectedStyle = FeedIconBackgroundStyle.light

        // Launch 5 tasks simultaneously for the same feedID.
        // The work closure delays 50ms so all callers are guaranteed to arrive
        // before the first task completes, ensuring coalescing is exercised.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    let result = await coordinator.coalesce(feedID: feedID) {
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
    func concurrentCallsForDifferentFeedIDsProceedIndependently() async {
        let coordinator = FeedIconResolutionCoordinator()
        let counter = CallCounter()
        let feedIDs = [UUID(), UUID(), UUID()]

        await withTaskGroup(of: Void.self) { group in
            for feedID in feedIDs {
                group.addTask {
                    _ = await coordinator.coalesce(feedID: feedID) {
                        await counter.increment()
                        return nil
                    }
                }
            }
        }

        let invokeCount = await counter.count
        #expect(invokeCount == feedIDs.count, "Work closure should run once per distinct feedID; ran \(invokeCount) times for \(feedIDs.count) feeds")
    }

    @Test("Completed entry is removed, allowing a fresh resolution on the next call")
    func completedEntryRemovedAllowsFreshResolution() async {
        let coordinator = FeedIconResolutionCoordinator()
        let counter = CallCounter()
        let feedID = UUID()

        // First call — completes normally.
        _ = await coordinator.coalesce(feedID: feedID) {
            await counter.increment()
            return nil
        }

        // Second call — must start fresh because the first entry was removed on completion.
        _ = await coordinator.coalesce(feedID: feedID) {
            await counter.increment()
            return nil
        }

        let invokeCount = await counter.count
        #expect(invokeCount == 2, "Work closure should run again after the first resolution completed; ran \(invokeCount) times")
    }
}
