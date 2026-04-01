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
│   ├── DOMNode.swift                   # SerializedDOM + DOMNode tree from domSerializer.js
│   ├── OPMLFeedEntry.swift              # Intermediate OPML parsed entry (title, feedURL, siteURL, description)
│   ├── OPMLImportResult.swift           # OPML import outcome counts (added, skipped, total)
│   ├── RSSFeed.swift                   # Feed container with channel info and articles
│   └── SubscribedFeed.swift            # Persistent feed subscription (Identifiable, Hashable, Codable, Sendable)
├── Services/                           # Business logic and networking
│   ├── ArticleExtractionService.swift  # WKWebView + domSerializer.js + native content extraction
│   ├── CandidateScorer.swift           # Readability-style DOM scoring to find article content node
│   ├── ClaudeAPIService.swift          # Claude API client — streaming SSE via URLSession
│   ├── ContentAssembler.swift          # Reconstructs clean HTML + plain text from winning DOM subtree
│   ├── ContentExtractor.swift          # ContentExtracting protocol + extraction pipeline orchestrator
│   ├── DOMSerializerConstants.swift    # Shared JS bridge constants (message handler name, serializer call)
│   ├── FeedFetchingService.swift       # FeedFetching protocol + URLSession implementation
│   ├── FeedStorageService.swift        # FeedStoring protocol + UserDefaults persistence for subscribed feeds
│   ├── HTMLUtilities.swift             # HTML tag stripping, entity decoding, image extraction
│   ├── KeychainService.swift           # Keychain wrapper for secure API key storage
│   ├── MetadataExtractor.swift         # Extracts article title/byline from meta tags and DOM elements
│   ├── OPMLService.swift               # OPMLServing protocol + XMLParser-based OPML parser + XML generator
│   ├── RSSParsingService.swift         # XMLParser-based RSS 2.0 parser
│   └── SiteSpecificExtracting.swift    # Protocol for per-hostname content extractors
├── ViewModels/                         # View state management
│   ├── AddFeedViewModel.swift          # @Observable @MainActor — URL validation + feed subscription
│   ├── ArticleSummaryViewModel.swift   # @Observable @MainActor — extraction state machine
│   ├── DiscussionViewModel.swift       # @Observable @MainActor — chat history + Claude streaming
│   ├── FeedListViewModel.swift         # @Observable @MainActor — subscribed feed list management
│   └── FeedViewModel.swift             # @Observable @MainActor — feed loading state
├── Views/                              # SwiftUI views
│   ├── ActivityShareView.swift          # UIViewControllerRepresentable wrapping UIActivityViewController
│   ├── AddFeedView.swift               # Sheet for adding a new feed — URL input + validation
│   ├── APIKeySettingsView.swift        # Keychain API key entry/removal UI
│   ├── ArticleDiscussionView.swift     # Chat sheet — message bubbles + streaming input
│   ├── ArticleListView.swift           # Feed article list with loading/error/content states
│   ├── ArticleReaderView.swift         # Full-screen reader — WKWebView + discuss/settings toolbar
│   ├── ArticleReaderWebView.swift      # UIViewRepresentable wrapping WKWebView with DOM serializer injection
│   ├── ArticleRowView.swift            # Single article row — thumbnail, title, snippet, date
│   ├── ArticleSummaryView.swift        # Extracted article summary sheet — extracted content + discuss
│   ├── ContentView.swift               # Root view — hosts FeedListView
│   ├── FeedListView.swift              # Subscribed feed list — NavigationStack root with add/remove
│   └── FeedRowView.swift               # Single feed row — title + description
└── Resources/
    ├── domSerializer.js                # Bundled DOM serializer — walks DOM tree, emits JSON for Swift extraction
    └── Assets.xcassets/                # App icons and image assets
        ├── AccentColor.colorset/       # App accent color
        └── AppIcon.appiconset/         # App icon (1024x1024 placeholder)

RSSAppTests/
├── RSSAppTests.swift                   # Root test suite (ContentView instantiation)
├── Fixtures/
│   └── simple-blog.html               # HTML test fixture for DOM serialization and pipeline tests
├── Helpers/
│   ├── DOMNodeTestHelpers.swift        # DOMNodeFactory — convenience builders for test DOM trees
│   ├── TestFixtures.swift              # Sample RSS XML, factory methods for Article/RSSFeed
│   └── WebViewTestHelpers.swift        # WKWebView-based serialization helpers for integration tests
├── Mocks/
│   ├── MockArticleExtractionService.swift  # ArticleExtracting mock with injectable content/errors
│   ├── MockClaudeAPIService.swift          # ClaudeAPIServicing mock with injectable chunks/errors
│   ├── MockContentExtractor.swift          # ContentExtracting mock with injectable results
│   ├── MockFeedFetchingService.swift       # FeedFetching mock with injectable results/errors
│   ├── MockFeedStorageService.swift        # FeedStoring mock with in-memory store
│   ├── MockKeychainService.swift           # KeychainServicing mock with in-memory store
│   └── MockOPMLService.swift               # OPMLServing mock with injectable entries/data/errors
├── Models/
│   ├── ArticleTests.swift              # Article creation, identity, hashable
│   └── DOMNodeTests.swift              # DOMNode accessors, text/element queries, tree traversal
├── Services/
│   ├── CandidateScorerTests.swift      # Content node identification, scoring, pruning
│   ├── ClaudeAPIServiceTests.swift     # Request encoding, SSE parsing, error handling
│   ├── ContentAssemblerTests.swift     # HTML/text assembly from DOM subtrees
│   ├── ContentExtractorTests.swift     # End-to-end extraction pipeline, site-specific fallback
│   ├── DOMSerializerTests.swift        # WKWebView integration — JS serialization fidelity
│   ├── ExtractionPipelineTests.swift   # Full pipeline: HTML → WKWebView serialize → Swift extract
│   ├── FeedStorageServiceTests.swift   # Save/load roundtrip, add/remove, empty state
│   ├── HTMLUtilitiesTests.swift        # Tag stripping, entity decoding, image extraction
│   ├── KeychainServiceTests.swift      # Save/load/delete/overwrite roundtrips
│   ├── OPMLServiceTests.swift          # Parse flat/nested/empty OPML, generate + round-trip, XML escaping
│   ├── MetadataExtractorTests.swift    # Title/byline extraction from meta tags and DOM
│   └── RSSParsingServiceTests.swift    # Channel parsing, thumbnails, IDs, edge cases
└── ViewModels/
    ├── AddFeedViewModelTests.swift         # URL validation, duplicate detection, success/failure
    ├── ArticleReaderViewModelTests.swift   # ArticleSummaryViewModel pre-extraction state tests
    ├── DiscussionViewModelTests.swift      # Message flow, streaming, no-key behavior
    ├── FeedListViewModelTests.swift        # Load, remove by object, remove by IndexSet
    └── FeedViewModelTests.swift            # Load success/failure, state transitions
```

**Total: 40 source files + 1 resource, 30 test source files + 1 fixture.**

## Component Map

### App Layer

**Files:** `RSSAppApp.swift`

`RSSAppApp` is the entry point. It declares a single `WindowGroup` scene containing `ContentView`. The app uses the SwiftUI App lifecycle — no `AppDelegate` or `SceneDelegate`.

### Models

**Files:** `Article.swift`, `ArticleContent.swift`, `ChatMessage.swift`, `DOMNode.swift`, `OPMLFeedEntry.swift`, `OPMLImportResult.swift`, `RSSFeed.swift`, `SubscribedFeed.swift`

`Article` is the core data model representing a single feed item. It stores the title, link, raw HTML description, a plain-text snippet, publication date, and thumbnail URL. It conforms to `Identifiable` (for lists), `Hashable` (for navigation), and `Sendable` (for concurrency safety).

`ArticleContent` holds the result of content extraction: `htmlContent` (clean HTML for display) and `textContent` (plain text for AI context), plus `title` and `byline`. Has a static `rssFallback(html:)` factory for graceful degradation.

`ChatMessage` represents a single turn in the discussion chat. `role` is `.user` or `.assistant`. `content` is mutable (`var`) to allow streaming chunks to be appended in place.

`DOMNode.swift` defines `SerializedDOM` (top-level page representation with title, URL, lang, meta tags, and body tree) and `DOMNode` (recursive tree node with tag name, attributes, visibility flag, and children). Both are `Codable` and `Sendable` value types. `CandidateScorer` internally wraps nodes in a reference-type `NodeWrapper` to add parent pointers during scoring.

`RSSFeed` represents a parsed feed channel — title, link, description, and an array of `Article` values. Also `Sendable`.

`SubscribedFeed` represents a persistent feed subscription — id, title, URL, description, and added date. Conforms to `Identifiable`, `Hashable`, `Codable` (for UserDefaults persistence), and `Sendable`.

`OPMLFeedEntry` is an intermediate type for parsed OPML feed entries — title, feed URL, optional site URL, and description. Decoupled from `SubscribedFeed` because OPML data lacks `id` and `addedDate`.

`OPMLImportResult` communicates import outcome to the UI — counts of added, skipped, and total feeds in the file.

### Services

**Files:** `ArticleExtractionService.swift`, `CandidateScorer.swift`, `ClaudeAPIService.swift`, `ContentAssembler.swift`, `ContentExtractor.swift`, `DOMSerializerConstants.swift`, `FeedFetchingService.swift`, `FeedStorageService.swift`, `HTMLUtilities.swift`, `KeychainService.swift`, `MetadataExtractor.swift`, `OPMLService.swift`, `RSSParsingService.swift`, `SiteSpecificExtracting.swift`

`FeedFetching` is a protocol defining `fetchFeed(from:) async throws -> RSSFeed`. `FeedFetchingService` fetches data via `URLSession.shared` and delegates parsing to `RSSParsingService`.

`RSSParsingService` wraps Foundation's `XMLParser` to parse RSS 2.0 XML. Internally uses a synchronous `XMLParserDelegate` class marked `@unchecked Sendable` (safe because it is created and consumed within a single synchronous `parse()` call).

`HTMLUtilities` provides static methods for stripping HTML tags/entities to plain text and extracting the first `<img>` URL.

**Native content extraction pipeline:** The app uses a custom Swift-native extraction pipeline (replacing Readability.js as of PR #3). The pipeline consists of:

- `ArticleExtractionService` — `@MainActor` service that loads the article URL in a hidden 1×1 `WKWebView`, injects `domSerializer.js` (which serializes the DOM tree to JSON), and bridges the result into Swift via `evaluateJavaScript`. Uses `withCheckedThrowingContinuation` + `WKNavigationDelegate` with a 35-second safety timeout. Falls back to the RSS `articleDescription` if extraction fails.
- `DOMSerializerConstants` — shared enum with the JS bridge constants (`messageHandlerName`, `serializerCall`) used by both `ArticleExtractionService` and `ArticleReaderWebView`.
- `ContentExtractor` — orchestrates the extraction pipeline: site-specific extractors → metadata extraction → candidate scoring → content assembly. Conforms to `ContentExtracting` protocol for testability.
- `CandidateScorer` — Readability-style algorithm that scores DOM nodes to find the article content container. Prunes unlikely nodes (nav, sidebar, footer), scores paragraphs and propagates to ancestors with decay, penalizes high link-density nodes.
- `ContentAssembler` — walks the winning DOM subtree and produces clean `htmlContent` (preserving semantic tags) and `textContent` (plain text with paragraph breaks).
- `MetadataExtractor` — extracts article title and byline from OpenGraph/article meta tags and DOM elements (`<h1>`, byline class patterns).
- `SiteSpecificExtracting` — extensibility protocol for per-hostname extractors. Implementations are checked before the generic algorithm runs.

`ClaudeAPIServicing` is a `Sendable` protocol. `ClaudeAPIService` POSTs to the Anthropic Messages API with `stream: true`, reads SSE lines via `URLSession.bytes(for:).lines`, and yields text deltas via `AsyncThrowingStream<String, Error>`.

`KeychainServicing` is a `Sendable` protocol. `KeychainService` wraps `Security` framework (`kSecClassGenericPassword`) to save, load, and delete the Anthropic API key. The key is stored encrypted by the OS and never touches any file accessible to git.

`FeedStoring` is a `Sendable` protocol. `FeedStorageService` persists the user's subscribed feed list in `UserDefaults` using `Codable` encoding. Accepts a `UserDefaults` instance in its initializer (defaults to `.standard`) for test isolation.

`OPMLServing` is a `Sendable` protocol. `OPMLService` handles OPML import/export. Parsing uses `XMLParser` with a private `OPMLParserDelegate` (same `@unchecked Sendable` pattern as `RSSParserDelegate`) that captures all `<outline>` elements with `xmlUrl` attributes regardless of nesting depth, flattening folders. Generation builds OPML 2.0 XML with proper XML escaping. Accepts outlines regardless of `type` attribute for maximum compatibility with real-world OPML files.

### ViewModels

**Files:** `AddFeedViewModel.swift`, `ArticleSummaryViewModel.swift`, `DiscussionViewModel.swift`, `FeedListViewModel.swift`, `FeedViewModel.swift`

All view models are `@MainActor @Observable`.

`FeedListViewModel` manages the subscribed feed list. Loads feeds from `FeedStoring`, supports removal by object or `IndexSet`, and OPML import/export via `OPMLServing`. `importOPML(from:)` parses OPML data, deduplicates against existing feeds and within the file, and merges new feeds. `exportOPML()` generates OPML data for sharing. Accepts `FeedStoring` and `OPMLServing` dependencies for testability.

`AddFeedViewModel` handles the add-feed flow: URL input, validation (scheme/host check, duplicate detection), fetching the feed to extract its title, and persisting via `FeedStoring`. Accepts both `FeedFetching` and `FeedStoring` dependencies for testability.

`FeedViewModel` holds the article list, feed title, loading state, and error state. Requires a `feedURL` parameter. Accepts a `FeedFetching` dependency for testability.

`ArticleSummaryViewModel` drives the article summary/extraction flow. Its `State` enum (`idle` / `extracting` / `ready(ArticleContent)` / `failed(String)`) reflects the extraction lifecycle. Stores `extractedContent` for use by the discussion sheet. Accepts an `ArticleExtracting` dependency for testability.

`DiscussionViewModel` manages the chat session. `sendMessage()` appends the user turn, appends an empty assistant placeholder, then streams Claude API response chunks into `messages[lastIndex].content`. Reads the API key from `KeychainServicing`. Accepts both `ClaudeAPIServicing` and `KeychainServicing` dependencies for testability.

### Views

**Files:** `ActivityShareView.swift`, `AddFeedView.swift`, `APIKeySettingsView.swift`, `ArticleDiscussionView.swift`, `ArticleListView.swift`, `ArticleReaderView.swift`, `ArticleReaderWebView.swift`, `ArticleRowView.swift`, `ArticleSummaryView.swift`, `ContentView.swift`, `FeedListView.swift`, `FeedRowView.swift`

`ContentView` hosts `FeedListView` as the root view.

`FeedListView` is the `NavigationStack` root. It shows the list of subscribed feeds using `FeedRowView` rows with `NavigationLink(value:)`. Empty state shows a `ContentUnavailableView` prompting the user to add a feed. Toolbar has add (+) and a menu (ellipsis.circle) with import feeds, export feeds, and settings options. Uses `.navigationDestination(for: SubscribedFeed.self)` to push `ArticleListView` with a `FeedViewModel` for the selected feed. Supports swipe-to-delete via `.onDelete`. OPML import uses `.fileImporter` accepting `.opml`/`.xml` files; export uses `ActivityShareView` to share a generated `.opml` file.

`ActivityShareView` is a `UIViewControllerRepresentable` wrapping `UIActivityViewController` for sharing exported OPML files.

`FeedRowView` displays a feed's title (`.headline`) and description (`.subheadline`, `.secondary`).

`AddFeedView` is a sheet with a `Form` for entering a feed URL. Shows validation progress and error states. Auto-dismisses on successful addition.

`ArticleListView` shows loading / error / list states. Uses `viewModel.feedTitle` as the navigation title. Tapping a row sets `selectedArticle`, triggering a `.fullScreenCover` with `ArticleReaderView`.

`ArticleRowView` displays a 60×60 `AsyncImage` thumbnail, headline title, subheadline snippet, and caption-style relative date.

`ArticleReaderView` is presented as a `fullScreenCover`. It hosts a `NavigationStack` with Done (dismiss), gear (settings), and sparkles (summarize) toolbar buttons. Contains `ArticleReaderWebView` for displaying the article and supports presenting `ArticleSummaryView` (for extraction) and `APIKeySettingsView` (for API key configuration) as sheets. The discussion flow is reached from within `ArticleSummaryView`. The `ArticleReaderWebView` coordinator performs early extraction via a `WKScriptMessageHandler`, making pre-extracted content available for the summary and discussion flows.

`ArticleReaderWebView` is a `UIViewRepresentable` wrapping `WKWebView`. It injects `domSerializer.js` at document end for early extraction, and its `Coordinator` handles both early extraction (via message handler) and fallback extraction (via `didFinish` delegate). Stores results in a shared `ReaderExtractionState` observable.

`ArticleSummaryView` is a sheet that displays extracted article content (title, byline, text) with a toolbar button to open the discussion. Uses `ArticleSummaryViewModel` for extraction state management.

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
                │                           ├── ArticleReaderWebView (visible WKWebView)
                │                           │   └── Coordinator (WKNavigationDelegate + WKScriptMessageHandler)
                │                           │       ├── Injects domSerializer.js at document end
                │                           │       ├── Early extraction via message handler → ReaderExtractionState
                │                           │       └── Fallback extraction via didFinish + evaluateJavaScript
                │                           │           └── Native extraction pipeline:
                │                           │               ├── ContentExtractor (orchestrator)
                │                           │               ├── MetadataExtractor → title, byline
                │                           │               ├── CandidateScorer → best content node
                │                           │               └── ContentAssembler → htmlContent + textContent
                │                           ├── sparkles button → sheet → ArticleSummaryView
                │                           │   ├── ArticleSummaryViewModel
                │                           │   │   └── ArticleExtractionService (hidden WKWebView)
                │                           │   │       └── Same native extraction pipeline
                │                           │   └── discuss button → sheet → ArticleDiscussionView
                │                           │       └── DiscussionViewModel
                │                           │           ├── KeychainService → Anthropic API key
                │                           │           └── ClaudeAPIService → URLSession SSE stream
                │                           └── gear button → sheet → APIKeySettingsView
                ├── OPML Import (via .fileImporter)
                │   └── viewModel.importOPML(from:)
                │       ├── OPMLService.parseOPML → [OPMLFeedEntry]
                │       ├── Deduplicate against existing feeds + intra-file
                │       └── FeedStorageService → persist merged list
                ├── OPML Export (via Menu)
                │   └── viewModel.exportOPML()
                │       ├── OPMLService.generateOPML → Data
                │       └── ActivityShareView → UIActivityViewController
                ├── Sheet: AddFeedView
                │   └── @State AddFeedViewModel
                │       ├── FeedFetchingService → validate URL + fetch title
                │       └── FeedStorageService → persist subscription
                └── Sheet: APIKeySettingsView
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
| Native Swift content extraction over Readability.js | Custom pipeline (CandidateScorer + ContentAssembler) adapted from Readability's algorithm; eliminates JS dependency; enables Swift-native testing and debugging |
| `domSerializer.js` for DOM serialization | Lightweight JS script that serializes the DOM tree to JSON for Swift-side processing; decouples DOM access (requires JS) from content extraction logic (pure Swift) |
| Fallback to RSS `articleDescription` | Graceful degradation when native extraction cannot parse a page |
| Thumbnail priority: media:thumbnail → media:content → enclosure → img in HTML | Covers common RSS image patterns; ordered by specificity |
| UserDefaults + Codable for feed persistence | Simplest option with no external deps; adequate for a small list of feeds |
| `SubscribedFeed` separate from `RSSFeed` | `RSSFeed` is transient parsed XML data; `SubscribedFeed` is persistent subscription metadata |
| `OPMLFeedEntry` intermediate type | Decouples OPML parser from persistence model; OPML data lacks `id`/`addedDate` fields |
| Manual XML generation for OPML export | `XMLDocument` is macOS-only; string building with XML escaping is sufficient for the simple OPML structure |
| OPML import accepts outlines without `type="rss"` | Real-world OPML files often omit the type attribute; any outline with a valid `xmlUrl` is treated as a feed |
| Feed title fetched at add-time | Validates the URL is a real feed; better UX than requiring manual title entry |
| `FeedViewModel` created per-navigation | Simple lifecycle; fresh fetch on each visit; no premature caching |

## Test Coverage

| Component | Test File | Coverage |
|-----------|-----------|----------|
| ContentView | RSSAppTests.swift | Verifies view instantiation |
| Article | ArticleTests.swift | Creation, nil optionals, Identifiable, Hashable, equality |
| DOMNode | DOMNodeTests.swift | Text/element accessors, tag name queries, tree traversal, visibility |
| HTMLUtilities | HTMLUtilitiesTests.swift | Tag stripping, entity decoding (amp, lt, gt, quot, apos, nbsp), whitespace collapse, image extraction (double/single quotes, multiple images, no images) |
| RSSParsingService | RSSParsingServiceTests.swift | Channel info, article count, basic fields, pubDate, snippets, raw description, thumbnail sources (media:thumbnail, media:content, enclosure, img fallback), thumbnail priority, ID derivation (guid, link), empty channel, malformed XML, empty data, missing fields, empty title, long snippet truncation |
| KeychainService | KeychainServiceTests.swift | Save/load roundtrip, load when empty, delete clears value, overwrite updates value |
| ClaudeAPIService | ClaudeAPIServiceTests.swift | Request headers, request body JSON encoding, SSE text delta parsing, non-delta event returns nil, malformed JSON returns nil, delta without text returns nil |
| CandidateScorer | CandidateScorerTests.swift | Content node identification in simple pages, scoring with class/id signals, link-density penalty, pruning of unlikely nodes |
| ContentAssembler | ContentAssemblerTests.swift | Plain text assembly, HTML tag preservation, attribute stripping, nested structure handling |
| ContentExtractor | ContentExtractorTests.swift | End-to-end extraction from DOM, site-specific extractor fallback, nil handling |
| MetadataExtractor | MetadataExtractorTests.swift | Title from OG meta, title from H1, byline from meta tags, byline from DOM elements |
| DOMSerializer (JS) | DOMSerializerTests.swift | WKWebView integration — text nodes, attributes, IDs, classes, ARIA roles, links, images, hidden elements, script/style filtering, meta tag capture, blog fixture serialization |
| Extraction Pipeline | ExtractionPipelineTests.swift | Full pipeline: HTML fixture → WKWebView serialize → Swift extract; JSON validity; meta tag capture |
| ArticleSummaryViewModel | ArticleReaderViewModelTests.swift | Pre-extracted content availability, extraction skip behavior, idle state |
| DiscussionViewModel | DiscussionViewModelTests.swift | hasAPIKey reflects keychain, send appends messages, chunks accumulate, input cleared, API error → error content, empty input ignored, no-key sets errorMessage |
| FeedViewModel | FeedViewModelTests.swift | Load success/failure, error clearing on retry, article replacement on refresh, isLoading state |
| FeedStorageService | FeedStorageServiceTests.swift | Save/load roundtrip, add, remove, empty state, overwrite |
| OPMLService | OPMLServiceTests.swift | Parse flat/nested/empty OPML, folder flattening, missing attributes, title fallbacks, malformed XML, no body, round-trip generation, XML escaping, structure validation |
| FeedListViewModel | FeedListViewModelTests.swift | Load from storage, remove by object, remove by IndexSet, empty state, OPML import (add new, skip duplicates, skip intra-file duplicates, result counts, save to storage, rollback on failure, parse error), OPML export (sets data, error on failure) |
| AddFeedViewModel | AddFeedViewModelTests.swift | Success, scheme prepend, invalid URL, duplicate detection, network error, error clearing |
