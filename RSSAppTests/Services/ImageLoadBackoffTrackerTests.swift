import Testing
import Foundation
@testable import RSSApp

@Suite("ImageLoadBackoffTracker Tests")
@MainActor
struct ImageLoadBackoffTrackerTests {

    // MARK: - Backoff Interval Calculation

    @Test("Backoff interval is zero for zero attempts")
    func backoffIntervalZeroAttempts() {
        let tracker = ImageLoadBackoffTracker(baseInterval: 30, maxInterval: 1800)

        #expect(tracker.backoffInterval(attemptCount: 0) == 0)
    }

    @Test("Backoff interval equals base interval on first attempt")
    func backoffIntervalFirstAttempt() {
        let tracker = ImageLoadBackoffTracker(baseInterval: 30, maxInterval: 1800)

        #expect(tracker.backoffInterval(attemptCount: 1) == 30)
    }

    @Test("Backoff interval doubles on each subsequent attempt")
    func backoffIntervalDoublesExponentially() {
        let tracker = ImageLoadBackoffTracker(baseInterval: 30, maxInterval: 1800)

        #expect(tracker.backoffInterval(attemptCount: 2) == 60)
        #expect(tracker.backoffInterval(attemptCount: 3) == 120)
        #expect(tracker.backoffInterval(attemptCount: 4) == 240)
    }

    @Test("Backoff interval is capped at maxInterval")
    func backoffIntervalCappedAtMax() {
        let tracker = ImageLoadBackoffTracker(baseInterval: 30, maxInterval: 1800)

        // 30 * 2^6 = 1920, which exceeds 1800 cap
        #expect(tracker.backoffInterval(attemptCount: 7) == 1800)
        #expect(tracker.backoffInterval(attemptCount: 10) == 1800)
    }

    // MARK: - Suppression Logic

    @Test("Does not suppress when no failure has been recorded")
    func noSuppressionWithoutFailure() {
        let tracker = ImageLoadBackoffTracker(baseInterval: 30, maxInterval: 1800)
        let key = "test-key"

        #expect(!tracker.shouldSuppress(key))
    }

    @Test("Suppresses immediately after recording failure")
    func suppressesAfterFailure() {
        let tracker = ImageLoadBackoffTracker(baseInterval: 30, maxInterval: 1800)
        let key = "test-key"

        tracker.recordFailure(for: key)

        #expect(tracker.shouldSuppress(key))
    }

    @Test("Does not suppress a different key after recording failure for another key")
    func suppressionIsolatedByKey() {
        let tracker = ImageLoadBackoffTracker(baseInterval: 30, maxInterval: 1800)

        tracker.recordFailure(for: "key-a")

        #expect(!tracker.shouldSuppress("key-b"))
    }

    @Test("Clearing failure allows immediate retry")
    func clearFailureAllowsRetry() {
        let tracker = ImageLoadBackoffTracker(baseInterval: 30, maxInterval: 1800)
        let key = "test-key"

        tracker.recordFailure(for: key)
        #expect(tracker.shouldSuppress(key))

        tracker.clearFailure(for: key)
        #expect(!tracker.shouldSuppress(key))
    }

    @Test("Does not suppress after backoff window expires")
    func noSuppressionAfterBackoffExpiry() async throws {
        // Use a tiny base interval so the backoff expires quickly
        let tracker = ImageLoadBackoffTracker(baseInterval: 0.001, maxInterval: 0.01)
        let key = "test-key"

        tracker.recordFailure(for: key)

        // Wait long enough for the 1ms backoff to expire
        try await Task.sleep(for: .milliseconds(20))
        #expect(!tracker.shouldSuppress(key))
    }

    @Test("Multiple failures increase the backoff window")
    func multipleFailuresIncreaseBackoff() {
        // Use a measurable but small interval to verify escalation
        let tracker = ImageLoadBackoffTracker(baseInterval: 60, maxInterval: 3600)
        let key = "test-key"

        // First failure: 60s backoff
        tracker.recordFailure(for: key)
        #expect(tracker.shouldSuppress(key))

        // Record a second failure: backoff should now be 120s
        tracker.recordFailure(for: key)
        #expect(tracker.shouldSuppress(key))

        // Record a third failure: backoff should now be 240s
        tracker.recordFailure(for: key)
        #expect(tracker.shouldSuppress(key))
    }

    @Test("Clear failure is idempotent for unknown keys")
    func clearFailureIdempotent() {
        let tracker = ImageLoadBackoffTracker(baseInterval: 30, maxInterval: 1800)

        // Should not crash or cause issues
        tracker.clearFailure(for: "never-recorded")
        #expect(!tracker.shouldSuppress("never-recorded"))
    }
}
