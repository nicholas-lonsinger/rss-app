import Foundation
import os

// MARK: - DiagnosticEvent

/// A single diagnostic emission — category, severity, and pre-formatted message.
///
/// Unlike `os.Logger`, which is the production logging backend, `DiagnosticEvent`
/// is plain value type so tests can assert on it directly. Production code that
/// cares about testing a fallback path calls both `logger.warning(...)` (for
/// developer diagnostics in Console.app) *and* `DiagnosticRecorder.record(...)`
/// (for the test seam). See the note on `DiagnosticRecorder` for why the two
/// mechanisms coexist.
struct DiagnosticEvent: Sendable, Equatable {
    /// Subsystem category that emitted the event — matches the `os.Logger`
    /// category used at the same call site (e.g. `"EncodingSniffer"`).
    let category: String

    /// Severity level. Mirrors the `os.Logger` call the call site makes.
    let level: Level

    /// Pre-formatted message. Call sites should include any interpolated values
    /// directly in the string (the recorder is off the hot path in production,
    /// so the formatting cost is only paid when tests are running).
    let message: String

    enum Level: String, Sendable, Equatable {
        case debug
        case info
        case notice
        case warning
        case error
        case fault
    }
}

// MARK: - DiagnosticSink

/// A sink that receives `DiagnosticEvent` values. Production never installs a
/// sink; tests install a recording sink to assert which fallback paths were hit.
protocol DiagnosticSink: Sendable {
    func record(_ event: DiagnosticEvent)
}

// MARK: - DiagnosticRecorder

/// A lightweight test seam for asserting that specific fallback paths were
/// exercised.
///
/// ## Why this exists
///
/// The production logging backend (`os.Logger`) is not easily observable from
/// unit tests: `OSLogStore` requires entitlements and does not work reliably on
/// iOS simulators, and `os.Logger`'s `OSLogMessage` interpolation makes a
/// transparent wrapper awkward because it would lose the privacy-marker and
/// zero-cost-formatting semantics. See GitHub issue #275 for the discussion.
///
/// Instead of replacing `os.Logger`, this type provides a **complementary**
/// recording channel. Production code that cares about testability at a given
/// call site emits to both:
///
/// ```swift
/// logger.warning("Unknown encoding name '\(name)'; falling back to UTF-8")
/// DiagnosticRecorder.record(
///     category: "EncodingSniffer",
///     level: .warning,
///     message: "Unknown encoding name '\(name)'; falling back to UTF-8"
/// )
/// ```
///
/// Tests install a sink via `install(_:)`, exercise the code under test, and
/// assert on the recorded events. In production `active` is always `nil`, so
/// `record(...)` is a cheap nil check on a lock-protected slot.
///
/// ## Adoption guidance
///
/// Adding a second call at every site is intentionally verbose — it keeps the
/// performance and privacy characteristics of `os.Logger` intact on the hot
/// path and lets us adopt the seam incrementally, starting with the call sites
/// flagged in code review (currently `EncodingSniffer`'s fallback paths).
/// Future services that want their warning/error paths to be asserted in tests
/// should follow the same dual-emission pattern.
///
/// ## Concurrency
///
/// The `active` sink is guarded by an `OSAllocatedUnfairLock` so installing,
/// reading, and removing the sink are safe from any thread. Tests are expected
/// to install the sink on the main thread before exercising code under test,
/// and remove it in a `defer` block; the lock is belt-and-suspenders protection
/// for code paths that run off the main actor.
enum DiagnosticRecorder {

    private static let slot = OSAllocatedUnfairLock<(any DiagnosticSink)?>(initialState: nil)

    /// Records a diagnostic event. No-op (single lock + nil check) when no sink
    /// is installed, which is the production case.
    static func record(category: String, level: DiagnosticEvent.Level, message: String) {
        let sink = slot.withLock { $0 }
        guard let sink else { return }
        sink.record(DiagnosticEvent(category: category, level: level, message: message))
    }

    /// Installs a sink. Returns the previously installed sink, if any, so tests
    /// can restore it in a `defer` block (e.g. when nested scopes install their
    /// own sinks).
    @discardableResult
    static func install(_ sink: any DiagnosticSink) -> (any DiagnosticSink)? {
        slot.withLock { state in
            let previous = state
            state = sink
            return previous
        }
    }

    /// Removes the currently installed sink. Safe to call when no sink is
    /// installed. Returns the removed sink, if any.
    @discardableResult
    static func uninstall() -> (any DiagnosticSink)? {
        slot.withLock { state in
            let previous = state
            state = nil
            return previous
        }
    }
}
