import Foundation

/// App-wide settings constants. Use `Settings.UserDefaultsKeys` to access
/// the shared `UserDefaults` key strings used across view models.
enum Settings {

    /// `UserDefaults` keys shared across multiple view models.
    ///
    /// Centralising these keys here prevents cross-component dependencies
    /// (e.g. `GroupArticleSource` importing `FeedViewModel` solely to read
    /// a key constant) and provides a single source of truth for the string
    /// values stored on disk.
    enum UserDefaultsKeys {

        /// Key for the app-wide sort order preference (`Bool` — `true` = ascending).
        /// Shared by `FeedViewModel`, `HomeViewModel`, and `GroupArticleSource`
        /// so all lists honour the same user-selected sort direction.
        static let sortAscending = "articleSortAscending"

        /// Key for the app-wide unread-only filter preference (`Bool`).
        /// Shared by `FeedViewModel` and `GroupArticleSource` so the toggle
        /// state is consistent regardless of which list the user is browsing.
        static let showUnreadOnly = "articleShowUnreadOnly"
    }
}
