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
│   └── RSSFeed.swift                   # Feed container with channel info and articles
├── Services/                           # Business logic and networking
│   ├── ArticleExtractionService.swift  # WKWebView + Readability.js content extraction
│   ├── ClaudeAPIService.swift          # Claude API client — streaming SSE via URLSession
│   ├── FeedFetchingService.swift       # FeedFetching protocol + URLSession implementation
│   ├── HTMLUtilities.swift             # HTML tag stripping, entity decoding, image extraction
│   ├── KeychainService.swift           # Keychain wrapper for secure API key storage
│   └── RSSParsingService.swift         # XMLParser-based RSS 2.0 parser
├── ViewModels/                         # View state management
│   ├── ArticleReaderViewModel.swift    # @Observable @MainActor — extraction state machine
│   ├── DiscussionViewModel.swift       # @Observable @MainActor — chat history + Claude streaming
│   └── FeedViewModel.swift             # @Observable @MainActor — feed loading state
├── Views/                              # SwiftUI views
│   ├── APIKeySettingsView.swift        # Keychain API key entry/removal UI
│   ├── ArticleDiscussionView.swift     # Chat sheet — message bubbles + streaming input
│   ├── ArticleListView.swift           # Feed article list with loading/error/content states
│   ├── ArticleReaderView.swift         # Full-screen reader — WKWebView + discuss/settings toolbar
│   ├── ArticleReaderWebView.swift      # UIViewRepresentable wrapping WKWebView with reader CSS
│   ├── ArticleRowView.swift            # Single article row — thumbnail, title, snippet, date
│   └── ContentView.swift               # Root view — NavigationStack with FeedViewModel
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
│   └── MockKeychainService.swift           # KeychainServicing mock with in-memory store
├── Models/
│   └── ArticleTests.swift              # Article creation, identity, hashable
├── Services/
│   ├── ClaudeAPIServiceTests.swift     # Request encoding, SSE parsing, error handling
│   ├── HTMLUtilitiesTests.swift        # Tag stripping, entity decoding, image extraction
│   ├── KeychainServiceTests.swift      # Save/load/delete/overwrite roundtrips
│   └── RSSParsingServiceTests.swift    # Channel parsing, thumbnails, IDs, edge cases
└── ViewModels/
    ├── ArticleReaderViewModelTests.swift   # State transitions: loading → loaded/failed
    ├── DiscussionViewModelTests.swift      # Message flow, streaming, no-key behavior
    └── FeedViewModelTests.swift            # Load success/failure, state transitions
```

**Total: 20 source files + 1 resource, 15 test files.**

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

### Services

**Files:** `ArticleExtractionService.swift`, `ClaudeAPIService.swift`, `FeedFetchingService.swift`, `HTMLUtilities.swift`, `KeychainService.swift`, `RSSParsingService.swift`

`FeedFetching` is a protocol defining `fetchFeed(from:) async throws -> RSSFeed`. `FeedFetchingService` fetches data via `URLSession.shared` and delegates parsing to `RSSParsingService`.

`RSSParsingService` wraps Foundation's `XMLParser` to parse RSS 2.0 XML. Internally uses a synchronous `XMLParserDelegate` class marked `@unchecked Sendable` (safe because it is created and consumed within a single synchronous `parse()` call).

`HTMLUtilities` provides static methods for stripping HTML tags/entities to plain text and extracting the first `<img>` URL.

`ArticleExtracting` is a `@MainActor` protocol. `ArticleExtractionService` loads the article URL in a hidden `WKWebView`, waits for navigation via `withCheckedThrowingContinuation` + `WKNavigationDelegate`, injects bundled `Readability.js`, calls `evaluateJavaScript` to extract content as JSON, and decodes it into `ArticleContent`. Falls back to the RSS `articleDescription` if Readability cannot parse the page.

`ClaudeAPIServicing` is a `Sendable` protocol. `ClaudeAPIService` POSTs to the Anthropic Messages API with `stream: true`, reads SSE lines via `URLSession.bytes(for:).lines`, and yields text deltas via `AsyncThrowingStream<String, Error>`.

`KeychainServicing` is a `Sendable` protocol. `KeychainService` wraps `Security` framework (`kSecClassGenericPassword`) to save, load, and delete the Anthropic API key. The key is stored encrypted by the OS and never touches any file accessible to git.

### ViewModels

**Files:** `ArticleReaderViewModel.swift`, `DiscussionViewModel.swift`, `FeedViewModel.swift`

All view models are `@MainActor @Observable`.

`FeedViewModel` holds the article list, loading state, and error state. Accepts a `FeedFetching` dependency for testability.

`ArticleReaderViewModel` drives the article reader. Its `State` enum (`loading` / `loaded(ArticleContent)` / `failed(String)`) reflects the extraction lifecycle. Accepts an `ArticleExtracting` dependency for testability.

`DiscussionViewModel` manages the chat session. `sendMessage()` appends the user turn, appends an empty assistant placeholder, then streams Claude API response chunks into `messages[lastIndex].content`. Reads the API key from `KeychainServicing`. Accepts both `ClaudeAPIServicing` and `KeychainServicing` dependencies for testability.

### Views

**Files:** `APIKeySettingsView.swift`, `ArticleDiscussionView.swift`, `ArticleListView.swift`, `ArticleReaderView.swift`, `ArticleReaderWebView.swift`, `ArticleRowView.swift`, `ContentView.swift`

`ContentView` creates a `FeedViewModel` as `@State` and wraps `ArticleListView` in a `NavigationStack`.

`ArticleListView` shows loading / error / list states. Tapping a row sets `selectedArticle`, triggering a `.fullScreenCover` with `ArticleReaderView`. A gear toolbar button opens `APIKeySettingsView`.

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
            ├── @State FeedViewModel
            │   ├── FeedFetchingService (FeedFetching protocol)
            │   │   ├── URLSession.shared → HTTP fetch
            │   │   └── RSSParsingService → XMLParser → [Article]
            │   ├── articles: [Article]
            │   ├── isLoading: Bool
            │   └── errorMessage: String?
            └── NavigationStack
                └── ArticleListView
                    ├── Loading → ProgressView
                    ├── Error → ContentUnavailableView + Retry
                    └── Content → List
                        └── ArticleRowView (thumbnail, title, snippet, date)
                            └── tap → fullScreenCover → ArticleReaderView
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
