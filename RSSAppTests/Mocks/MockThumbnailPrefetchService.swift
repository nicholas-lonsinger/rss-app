import Foundation
@testable import RSSApp

@MainActor
final class MockThumbnailPrefetchService: ThumbnailPrefetching {

    var prefetchCallCount = 0
    /// Optional continuation to signal when `prefetchThumbnails` is called.
    /// Useful for tests that need to wait for the fire-and-forget prefetch Task.
    var prefetchContinuation: CheckedContinuation<Void, Never>?

    func prefetchThumbnails() async {
        prefetchCallCount += 1
        prefetchContinuation?.resume()
        prefetchContinuation = nil
    }
}
