# Architecture

## Overview

RSS App is an iOS application for reading and managing RSS feeds. It is built as a pure SwiftUI app using the `@main` App lifecycle, targeting iOS 26 (iPhone only) with Swift 6 strict concurrency. There are no external package dependencies — the app uses only Apple system frameworks (`Foundation`, `WebKit`, `SafariServices`, `Security`).

## Directory Structure

```
RSSApp/
├── App/                                # App lifecycle
│   └── RSSAppApp.swift                 # @main entry point — WindowGroup with ContentView
├── Models/                             # Data models
│   ├── Article.swift                   # Article (Identifiable, Hashable, Sendable)
│   ├── ArticleContent.swift            # Extracted article data — htmlContent + textContent
│   ├── ChatMessage.swift               # Chat message with role (user/assistant) and content
│   ├── RSSFeed.swift                   # Feed container with channel info and articles
│   └── SubscribedFeed.swift            # Persistent feed subscription (Identifiable, Hashable, Codable, Sendable)
├── Services/                           # Business logic and networking
│   ├── ArticleExtractionService.swift  # WKWebView + Readability.js content extraction
│   ├── ClaudeAPIService.swift          # Claude API client — streaming SSE via URLSession
│   ├── FeedFetchingService.swift       # FeedFetching protocol + URLSession implementation
│   ├── FeedStorageService.swift        # FeedStoring protocol + UserDefaults persistence for subscribed feeds
│   ├── HTMLUtilities.swift             # HTML tag stripping, entity decoding, image extraction
│   ├── KeychainService.swift           # Keychain wrapper for secure API key storage
│   └── RSSParsingService.swift         # XMLParser-based RSS 2.0 parser
├── ViewModels/                         # View state management
│   ├── AddFeedViewModel.swift          # @Observable @MainActor — URL validation + feed subscription
│   ├── ArticleReaderViewModel.swift    # @Observable @MainActor — extraction state machine
│   ├── DiscussionViewModel.swift       # @Observable @MainActor — chat history + Claude streaming
│   ├── FeedListViewModel.swift         # @Observable @MainActor — subscribed feed list management
│   └── FeedViewModel.swift             # @Observable @MainActor — feed loading state
├── Views/                              # SwiftUI views
│   ├── AddFeedView.swift               # Sheet for adding a new feed — URL input + validation
│   ├── APIKeySettingsView.swift        # Keychain API key entry/removal UI
│   ├── ArticleDiscussionView.swift     # Chat sheet — message bubbles + streaming input
│   ├── ArticleListView.swift           # Feed article list with loading/error/content states
│   ├── ArticleReaderView.swift         # Full-screen reader — WKWebView + discuss/settings toolbar
│   ├── ArticleReaderWebView.swift      # UIViewRepresentable wrapping WKWebView with reader CSS
│   ├── ArticleRowView.swift            # Single article row — thumbnail, title, snippet, date
│   ├── ContentView.swift               # Root view — hosts FeedListView
│   ├── FeedListView.swift              # Subscribed feed list — NavigationStack root with add/remove
│   └── FeedRowView.swift               # Single feed row — title + description
└── Resources/
    ├── readability.js                  # Bundled Mozilla Readability.js (~91 KB)
    └── Assets.xcassets/                # App icons and image assets
        ├── AccentColor.colorset/       # App accent color
        └── AppIcon.appiconset/         # App icon (1024x1024 placeholder)

RSSAppTests/
├── RSSAppTests.swift                   # Root test suite (ContentView instantiation)
├── Helpers/
│   └── TestFixtures.swift              # Sample RSS XML, factory methods for Article/RSSFeed
├── Mocks/
│   ├── MockArticleExtractionService.swift  # ArticleExtracting mock with injectable content/errors
│   ├── MockClaudeAPIService.swift          # ClaudeAPIServicing mock with injectable chunks/errors
│   ├── MockFeedFetchingService.swift       # FeedFetching mock with injectable results/errors
│   ├── MockFeedStorageService.swift        # FeedStoring mock with in-memory store
│   └── MockKeychainService.swift           # KeychainServicing mock with in-memory store
├── Models/
│   └── ArticleTests.swift              # Article creation, identity, hashable
├── Services/
│   ├── ClaudeAPIServiceTests.swift     # Request encoding, SSE parsing, error handling
│   ├── FeedStorageServiceTests.swift   # Save/load roundtrip, add/remove, empty state
│   ├── HTMLUtilitiesTests.swift        # Tag stripping, entity decoding, image extraction
│   ├── KeychainServiceTests.swift      # Save/load/delete/overwrite roundtrips
│   └── RSSParsingServiceTests.swift    # Channel parsing, thumbnails, IDs, edge cases
└── ViewModels/
    ├── AddFeedViewModelTests.swift         # URL validation, duplicate detection, success/failure
    ├── ArticleReaderViewModelTests.swift   # State transitions: loading → loaded/failed
    ├── DiscussionViewModelTests.swift      # Message flow, streaming, no-key behavior
    ├── FeedListViewModelTests.swift        # Load, remove by object, remove by IndexSet
    └── FeedViewModelTests.swift            # Load success/failure, state transitions
```

**Total: 26 source files + 1 resource, 19 test files.**

## Component Map

### App Layer

**Files:** `RSSAppApp.swift`

`RSSAppApp` is the entry point. It declares a single `WindowGroup` scene containing `ContentView`. The app uses the SwiftUI App lifecycle — no `AppDelegate` or `SceneDelegate`.

### Models

**Files:** `Article.swift`, `ArticleContent.swift`, `ChatMessage.swift`, `RSSFeed.swift`

`Article` is the core data model representing a single feed item. It stores the title, link, raw HTML description, a plain-text snippet, publication date, and thumbnail URL. It conforms to `Identifiable` (for lists), `Hashable` (for navigation), and `Sendable` (for concurrency safety).

`ArticleContent` holds the result of Readability extraction: `htmlContent` (clean HTML for display) and `textContent` (plain text for AI context), plus `title` and `byline`.

`ChatMessage` represents a single turn in the discussion chat. `role` is `.user` or `.assistant`. `content` is mutable (`var`) to allow streaming chunks to be appended in place.

`RSSFeed` represents a parsed feed channel — title, link, description, and an array of `Article` values. Also `Sendable`.

`SubscribedFeed` represents a persistent feed subscription — id, title, URL, description, and added date. Conforms to `Identifiable`, `Hashable`, `Codable` (for UserDefaults persistence), and `Sendable`.

### Services

**Files:** `ArticleExtractionService.swift`, `ClaudeAPIService.swift`, `FeedFetchingService.swift`, `FeedStorageService.swift`, `HTMLUtilities.swift`, `KeychainService.swift`, `RSSParsingService.swift`

`FeedFetching` is a protocol defining `fetchFeed(from:) async throws -> RSSFeed`. `FeedFetchingService` fetches data via `URLSession.shared` and delegates parsing to `RSSParsingService`.

`RSSParsingService` wraps Foundation's `XMLParser` to parse RSS 2.0 XML. Internally uses a synchronous `XMLParserDelegate` class marked `@unchecked Sendable` (safe because it is created and consumed within a single synchronous `parse()` call).

`HTMLUtilities` provides static methods for stripping HTML tags/entities to plain text and extracting the first `<img>` URL.

`ArticleExtracting` is a `@MainActor` protocol. `ArticleExtractionService` loads the article URL in a hidden `WKWebView`, waits for navigation via `withCheckedThrowingContinuation` + `WKNavigationDelegate`, injects bundled `Readability.js`, calls `evaluateJavaScript` to extract content as JSON, and decodes it into `ArticleContent`. Falls back to the RSS `articleDescription` if Readability cannot parse the page.

`ClaudeAPIServicing` is a `Sendable` protocol. `ClaudeAPIService` POSTs to the Anthropic Messages API with `stream: true`, reads SSE lines via `URLSession.bytes(for:).lines`, and yields text deltas via `AsyncThrowingStream<String, Error>`.

`KeychainServicing` is a `Sendable` protocol. `KeychainService` wraps `Security` framework (`kSecClassGenericPassword`) to save, load, and delete the Anthropic API key. The key is stored encrypted by the OS and never touches any file accessible to git.

`FeedStoring` is a `Sendable` protocol. `FeedStorageService` persists the user's subscribed feed list in `UserDefaults` using `Codable` encoding. Accepts a `UserDefaults` instance in its initializer (defaults to `.standard`) for test isolation.

### ViewModels

**Files:** `AddFeedViewModel.swift`, `ArticleReaderViewModel.swift`, `DiscussionViewModel.swift`, `FeedListViewModel.swift`, `FeedViewModel.swift`

All view models are `@MainActor @Observable`.

`FeedListViewModel` manages the subscribed feed list. Loads feeds from `FeedStoring`, supports removal by object or `IndexSet`. Accepts a `FeedStoring` dependency for testability.

`AddFeedViewModel` handles the add-feed flow: URL input, validation (scheme/host check, duplicate detection), fetching the feed to extract its title, and persisting via `FeedStoring`. Accepts both `FeedFetching` and `FeedStoring` dependencies for testability.

`FeedViewModel` holds the article list, feed title, loading state, and error state. Requires a `feedURL` parameter. Accepts a `FeedFetching` dependency for testability.

`ArticleReaderViewModel` drives the article reader. Its `State` enum (`loading` / `loaded(ArticleContent)` / `failed(String)`) reflects the extraction lifecycle. Accepts an `ArticleExtracting` dependency for testability.

`DiscussionViewModel` manages the chat session. `sendMessage()` appends the user turn, appends an empty assistant placeholder, then streams Claude API response chunks into `messages[lastIndex].content`. Reads the API key from `KeychainServicing`. Accepts both `ClaudeAPIServicing` and `KeychainServicing` dependencies for testability.

### Views

**Files:** `AddFeedView.swift`, `APIKeySettingsView.swift`, `ArticleDiscussionView.swift`, `ArticleListView.swift`, `ArticleReaderView.swift`, `ArticleReaderWebView.swift`, `ArticleRowView.swift`, `ContentView.swift`, `FeedListView.swift`, `FeedRowView.swift`

`ContentView` hosts `FeedListView` as the root view.

`FeedListView` is the `NavigationStack` root. It shows the list of subscribed feeds using `FeedRowView` rows with `NavigationLink(value:)`. Empty state shows a `ContentUnavailableView` prompting the user to add a feed. Toolbar has add (+) and settings (gear) buttons. Uses `.navigationDestination(for: SubscribedFeed.self)` to push `ArticleListView` with a `FeedViewModel` for the selected feed. Supports swipe-to-delete via `.onDelete`.

`FeedRowView` displays a feed's title (`.headline`) and description (`.subheadline`, `.secondary`).

`AddFeedView` is a sheet with a `Form` for entering a feed URL. Shows validation progress and error states. Auto-dismisses on successful addition.

`ArticleListView` shows loading / error / list states. Uses `viewModel.feedTitle` as the navigation title. Tapping a row sets `selectedArticle`, triggering a `.fullScreenCover` with `ArticleReaderView`.

`ArticleRowView` displays a 60×60 `AsyncImage` thumbnail, headline title, subheadline snippet, and caption-style relative date.

`ArticleReaderView` is presented as a `fullScreenCover`. It hosts a `NavigationStack` with Done (dismiss), gear (settings), and chat bubble (discuss) toolbar buttons. Content switches between `ProgressView`, `ArticleReaderWebView`, and an error `ContentUnavailableView` based on `ArticleReaderViewModel.state`. The discuss button is disabled until content is loaded.

`ArticleReaderWebView` is a `UIViewRepresentable` wrapping `WKWebView`. It renders `ArticleContent.htmlContent` wrapped in a reader-mode HTML template (system font, `max-width: 680px`, dark-mode CSS via `@media (prefers-color-scheme: dark)`).

`ArticleDiscussionView` is a sheet. It shows a `ScrollViewReader`-driven chat list with user (blue, right-aligned) and assistant (grey, left-aligned) message bubbles, and a text input bar. When no API key is configured, a `ContentUnavailableView` prompt replaces the chat.

`APIKeySettingsView` provides a `SecureField` for pasting an Anthropic API key, Save/Remove buttons, and a status indicator. Saved keys go directly to `KeychainService`.

## Data Flow

```
RSSAppApp (@main)
    └── WindowGroup
        └── ContentView
            └── FeedListView
                ├── @State FeedListViewModel
                │   └── FeedStorageService (FeedStoring protocol)
                │       └── UserDefaults → [SubscribedFeed]
                ├── NavigationStack
                │   ├── Empty → ContentUnavailableView + "Add Feed" button
                │   └── List → FeedRowView (title, description)
                │       └── NavigationLink(value: SubscribedFeed)
                │           └── .navigationDestination → ArticleListView
                │               ├── FeedViewModel(feedURL: feed.url)
                │               │   ├── FeedFetchingService (FeedFetching protocol)
                │               │   │   ├── URLSession.shared → HTTP fetch
                │               │   │   └── RSSParsingService → XMLParser → [Article]
                │               │   ├── articles: [Article]
                │               │   ├── feedTitle: String
                │               │   ├── isLoading: Bool
                │               │   └── errorMessage: String?
                │               ├── Loading → ProgressView
                │               ├── Error → ContentUnavailableView + Retry
                │               └── Content → List
                │                   └── ArticleRowView (thumbnail, title, snippet, date)
                │                       └── tap → fullScreenCover → ArticleReaderView
                ├── Sheet: AddFeedView
                │   └── @State AddFeedViewModel
                │       ├── FeedFetchingService → validate URL + fetch title
                │       └── FeedStorageService → persist subscription
                └── Sheet: APIKeySettingsView
                                ├── ArticleReaderViewModel
                                │   └── ArticleExtractionService
                                │       ├── hidden WKWebView → load article URL
                                │       ├── inject readability.js → evaluateJavaScript
                                │       └── ArticleContent (htmlContent + textContent)
                                ├── ArticleReaderWebView (visible WKWebView, reader CSS)
                                └── discuss button → sheet → ArticleDiscussionView
                                    └── DiscussionViewModel
                                        ├── KeychainService → Anthropic API key
                                        └── ClaudeAPIService → URLSession SSE stream
```

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Pure SwiftUI App lifecycle | Simplest approach for a new iOS app; no UIKit boilerplate needed |
| Swift 6 strict concurrency | Catches data races at compile time; aligns with Apple's direction |
| No external dependencies | Reduces maintenance burden; all required capabilities exist in Apple frameworks |
| iPhone only (TARGETED_DEVICE_FAMILY = 1) | Focused initial scope; iPad support can be added later |
| PBXFileSystemSynchronizedRootGroup | Modern Xcode project format — filesystem auto-syncs with project, no manual file reference management |
| Swift Testing over XCTest | Modern test framework with cleaner syntax (@Test, #expect) |
| `@Observable` over `ObservableObject` | Modern observation API; less boilerplate (no `@Published`); better performance |
| Protocol DI for all services | Enables mock injection for ViewModel tests without network/keychain/WebView access |
| `XMLParser` with `@unchecked Sendable` delegate | Synchronous parsing within a single method call; delegate never escapes scope |
| `@MainActor` for `ArticleExtractionService` | `WKWebView` requires main-thread access; `@MainActor` enforces this at compile time |
| `@unchecked Sendable` on `ExtractionCoordinator` | Coordinator is only accessed on MainActor; lifecycle is bounded by a single extraction call |
| Keychain for API key storage | Encrypted by OS, sandboxed to app, never touches any file tracked by git |
| `AsyncThrowingStream` for Claude streaming | Composable with `for try await` syntax; isolates SSE parsing inside the service |
| Readability.js bundled in app | Mozilla's proven extraction algorithm; no server required; single 91 KB file |
| Fallback to RSS `articleDescription` | Graceful degradation when Readability cannot parse a page |
| Thumbnail priority: media:thumbnail → media:content → enclosure → img in HTML | Covers common RSS image patterns; ordered by specificity |
| UserDefaults + Codable for feed persistence | Simplest option with no external deps; adequate for a small list of feeds |
| `SubscribedFeed` separate from `RSSFeed` | `RSSFeed` is transient parsed XML data; `SubscribedFeed` is persistent subscription metadata |
| Feed title fetched at add-time | Validates the URL is a real feed; better UX than requiring manual title entry |
| `FeedViewModel` created per-navigation | Simple lifecycle; fresh fetch on each visit; no premature caching |

## Test Coverage

| Component | Test File | Coverage |
|-----------|-----------|----------|
| ContentView | RSSAppTests.swift | Verifies view instantiation |
| Article | ArticleTests.swift | Creation, nil optionals, Identifiable, Hashable, equality |
| HTMLUtilities | HTMLUtilitiesTests.swift | Tag stripping, entity decoding (amp, lt, gt, quot, apos, nbsp), whitespace collapse, image extraction (double/single quotes, multiple images, no images) |
| RSSParsingService | RSSParsingServiceTests.swift | Channel info, article count, basic fields, pubDate, snippets, raw description, thumbnail sources (media:thumbnail, media:content, enclosure, img fallback), thumbnail priority, ID derivation (guid, link), empty channel, malformed XML, empty data, missing fields, empty title, long snippet truncation |
| KeychainService | KeychainServiceTests.swift | Save/load roundtrip, load when empty, delete clears value, overwrite updates value |
| ClaudeAPIService | ClaudeAPIServiceTests.swift | Request headers, request body JSON encoding, SSE text delta parsing, non-delta event returns nil, malformed JSON returns nil, delta without text returns nil |
| ArticleReaderViewModel | ArticleReaderViewModelTests.swift | Initial state is loading, success → loaded, error → failed, nil link → failed |
| DiscussionViewModel | DiscussionViewModelTests.swift | hasAPIKey reflects keychain, send appends messages, chunks accumulate, input cleared, API error → error content, empty input ignored, no-key sets errorMessage |
| FeedViewModel | FeedViewModelTests.swift | Load success, load failure, error clearing on retry, article replacement on refresh, isLoading state |
| FeedStorageService | FeedStorageServiceTests.swift | Save/load roundtrip, add, remove, empty state, overwrite |
| FeedListViewModel | FeedListViewModelTests.swift | Load from storage, remove by object, remove by IndexSet, empty state |
| AddFeedViewModel | AddFeedViewModelTests.swift | Success, scheme prepend, invalid URL, duplicate detection, network error, error clearing |
