import Foundation
@testable import RSSApp

/// Test-only sink that records every `DiagnosticEvent` emitted through
/// `DiagnosticRecorder` while the sink is installed.
///
/// ## Usage
///
/// ```swift
/// let sink = RecordingDiagnosticSink()
/// DiagnosticRecorder.install(sink)
/// defer { DiagnosticRecorder.uninstall() }
///
/// // ... exercise code under test ...
///
/// #expect(sink.events(atLevel: .warning).contains { $0.message.contains("fallback") })
/// ```
///
/// The sink is backed by an `NSLock` so it is safe to record events from any
/// thread. Tests typically access events from the test runner thread only, but
/// the locking keeps the sink honest if code under test logs from a background
/// actor.
///
/// RATIONALE: `@unchecked Sendable` is acceptable because the recorder's
/// internal state is guarded by an `NSLock` and the class is only used from
/// tests, where single-ownership is easy to reason about.
final class RecordingDiagnosticSink: DiagnosticSink, @unchecked Sendable {

    private let lock = NSLock()
    private var _events: [DiagnosticEvent] = []

    init() {}

    func record(_ event: DiagnosticEvent) {
        lock.lock()
        _events.append(event)
        lock.unlock()
    }

    /// All events recorded so far, in emission order.
    var events: [DiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }

    /// Events filtered to the given severity level.
    func events(atLevel level: DiagnosticEvent.Level) -> [DiagnosticEvent] {
        events.filter { $0.level == level }
    }

    /// Events filtered to a given category.
    func events(inCategory category: String) -> [DiagnosticEvent] {
        events.filter { $0.category == category }
    }

    /// Clears the recorded events. Useful when reusing a single sink across
    /// multiple assertions in the same test.
    func reset() {
        lock.lock()
        _events.removeAll()
        lock.unlock()
    }
}
