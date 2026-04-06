/// Result of a pagination load-more operation, distinguishing between
/// successfully loaded articles, an exhausted data source (no more pages),
/// and a failed database query.
enum LoadMoreResult: Equatable, Sendable {
    /// New articles were successfully loaded.
    case loaded
    /// No more articles are available (data source exhausted).
    case exhausted
    /// The load operation failed with an error message.
    case failed(String)
}
