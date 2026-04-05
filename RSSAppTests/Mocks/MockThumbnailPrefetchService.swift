import Foundation
@testable import RSSApp

@MainActor
final class MockThumbnailPrefetchService: ThumbnailPrefetching {

    var prefetchCallCount = 0

    func prefetchThumbnails(persistence: FeedPersisting) async {
        prefetchCallCount += 1
    }
}
