import Foundation
import os

/// In-memory tracker that suppresses repeated image-fetch attempts after a failure.
///
/// Both `FeedIconView` (on-view icon resolution) and `ArticleThumbnailView`
/// (on-view thumbnail resolution) use this tracker to avoid hammering the
/// network when a fetch fails. State is in-memory only — it resets on app
/// launch, which is acceptable because the failure conditions (network errors,
/// 404s, invalid images) are typically transient across sessions.
///
/// Backoff uses exponential intervals starting at 30 seconds and capped at
/// 30 minutes: 30s, 60s, 120s, 240s, 480s, 960s, 1800s (cap).
@MainActor
final class ImageLoadBackoffTracker {

    private static let logger = Logger(category: "ImageLoadBackoffTracker")

    /// Shared instance for feed icon on-view resolution.
    static let feedIcons = ImageLoadBackoffTracker()

    /// Shared instance for article thumbnail on-view resolution.
    static let thumbnails = ImageLoadBackoffTracker()

    // MARK: - Configuration

    /// Base backoff interval after the first failure (30 seconds).
    private let baseInterval: TimeInterval

    /// Maximum backoff interval (30 minutes).
    private let maxInterval: TimeInterval

    private struct FailureRecord {
        var lastFailureDate: Date
        var attemptCount: Int
    }

    /// Maps a string key (feed UUID for icons, article ID for thumbnails)
    /// to its failure record.
    private var failures: [String: FailureRecord] = [:]

    init(baseInterval: TimeInterval = 30, maxInterval: TimeInterval = 1800) {
        precondition(baseInterval >= 0, "baseInterval must be non-negative")
        precondition(maxInterval >= baseInterval, "maxInterval must be >= baseInterval")
        self.baseInterval = baseInterval
        self.maxInterval = maxInterval
    }

    // MARK: - Public API

    /// Returns `true` if a fetch for `key` should be suppressed because the
    /// backoff window has not yet elapsed since the last failure.
    func shouldSuppress(_ key: String) -> Bool {
        guard let record = failures[key] else { return false }
        let elapsed = Date().timeIntervalSince(record.lastFailureDate)
        let backoff = backoffInterval(attemptCount: record.attemptCount)
        let suppress = elapsed < backoff
        if suppress {
            Self.logger.debug("Suppressing fetch for '\(key, privacy: .public)' — \(Int(backoff - elapsed), privacy: .public)s remaining in backoff window")
        }
        return suppress
    }

    /// Records a failed fetch for `key`, incrementing the attempt counter and
    /// resetting the backoff timer.
    func recordFailure(for key: String) {
        let existing = failures[key]
        let newCount = (existing?.attemptCount ?? 0) + 1
        failures[key] = FailureRecord(lastFailureDate: Date(), attemptCount: newCount)
        let interval = backoffInterval(attemptCount: newCount)
        Self.logger.debug("Recorded failure #\(newCount, privacy: .public) for '\(key, privacy: .public)' — next retry in \(Int(interval), privacy: .public)s")
    }

    /// Clears the backoff state for `key` after a successful fetch.
    func clearFailure(for key: String) {
        if failures.removeValue(forKey: key) != nil {
            Self.logger.debug("Cleared backoff state for '\(key, privacy: .public)'")
        }
    }

    // MARK: - Internal (visible to tests)

    /// Computes the backoff interval for a given attempt count.
    /// Formula: min(baseInterval * 2^(attemptCount - 1), maxInterval)
    nonisolated func backoffInterval(attemptCount: Int) -> TimeInterval {
        guard attemptCount > 0 else { return 0 }
        let exponent = min(attemptCount - 1, 20) // cap exponent to avoid overflow
        let interval = baseInterval * pow(2.0, Double(exponent))
        return min(interval, maxInterval)
    }
}
