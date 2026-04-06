# Architecture

## Overview

RSS App is an iOS application for reading and managing RSS feeds. It is built as a pure SwiftUI app using the `@main` App lifecycle, targeting iOS 26 (iPhone only) with Swift 6 strict concurrency. There are no external package dependencies — the app uses only Apple system frameworks (`Foundation`, `SwiftData`, `WebKit`, `SafariServices`, `Security`).

## Directory Structure

```
RSSApp/
├── App/                                # App lifecycle
│   └── RSSAppApp.swift                 # @main entry point — ModelContainer + WindowGroup with ContentView
├── Models/                             # Data models
│   ├── Article.swift                   # Article struct — transient parser output (Identifiable, Hashable, Sendable)
│   ├── ArticleContent.swift            # Extracted article data — htmlContent + textContent
│   ├── ChatMessage.swift               # Chat message with role (user/assistant) and content
│   ├── DOMNode.swift                   # SerializedDOM + DOMNode tree from domSerializer.js
│   ├── HomeGroup.swift                 # Enum — Home screen group types (allArticles, unreadArticles, allFeeds) with Identifiable, Hashable, CaseIterable
│   ├── ModelConversion.swift           # Bidirectional conversion: PersistentFeed↔SubscribedFeed, PersistentArticle↔Article, PersistentArticleContent↔ArticleContent
│   ├── OPMLFeedEntry.swift              # Intermediate OPML parsed entry (title, feedURL, siteURL, description)
│   ├── OPMLImportResult.swift           # OPML import outcome counts (added, skipped, total)
│   ├── PersistentArticle.swift         # @Model — persisted article with read/unread status, relationship to feed and content
│   ├── PersistentArticleContent.swift  # @Model — cached extracted HTML/text content, relationship to article
│   ├── PersistentFeed.swift            # @Model — persisted feed subscription with caching headers, icon URL, cascade to articles
│   ├── RSSFeed.swift                   # Feed container with channel info, imageURL, and articles (transient parser output)
│   └── SubscribedFeed.swift            # Legacy feed subscription struct (Codable) — retained for UserDefaults migration and OPML export
├── Services/                           # Business logic and networking
│   ├── ArticleExtractionService.swift  # WKWebView + domSerializer.js + native content extraction
│   ├── CandidateScorer.swift           # Readability-style DOM scoring to find article content node
│   ├── ClaudeAPIService.swift          # Claude API client — streaming SSE via URLSessionBytesProviding (injectable, defaults to URLSession.shared)
│   ├── ContentAssembler.swift          # Reconstructs clean HTML + plain text from winning DOM subtree
│   ├── ContentExtractor.swift          # ContentExtracting protocol + extraction pipeline orchestrator
│   ├── DOMSerializerConstants.swift    # Shared JS bridge constants (message handler name, serializer call)
│   ├── FeedFetchingService.swift       # FeedFetching protocol + URLSession implementation
│   ├── ArticleThumbnailService.swift   # ArticleThumbnailCaching protocol + thumbnail download, resize-to-120px, JPEG disk caching
│   ├── FeedIconService.swift           # FeedIconResolving protocol + icon URL resolution (feed XML → site HTML → /favicon.ico) and file-system caching
│   ├── FeedPersistenceService.swift    # FeedPersisting protocol + SwiftData implementation (feeds, articles, content cache, read/unread, bulk mark all read, sort order)
│   ├── FeedStorageService.swift        # FeedStoring protocol + UserDefaults persistence — retained for migration only
│   ├── FeedURLValidator.swift          # Shared URL normalization + validation (trim, scheme prepend, HTTP/HTTPS + host check)
│   ├── UserDefaultsMigrationService.swift # One-time migration from UserDefaults SubscribedFeed list to SwiftData PersistentFeed
│   ├── HTMLUtilities.swift             # HTML/XML escaping (text + attributes), tag stripping, entity decoding, image extraction, og:image extraction, icon URL extraction
│   ├── KeychainService.swift           # Keychain wrapper for secure API key storage
│   ├── MetadataExtractor.swift         # Extracts article title/byline from meta tags and DOM elements
│   ├── ModelConfigurationValidator.swift # ModelValidation + MaxTokensValidation enums — input validation for model ID and max tokens
│   ├── OPMLService.swift               # OPMLServing protocol + XMLParser-based OPML parser + XML generator
│   ├── RSSParsingService.swift         # XMLParser-based RSS 2.0 + Atom parser with XHTML content reconstruction
│   ├── SiteSpecificExtracting.swift    # Protocol for per-hostname content extractors
│   └── ThumbnailPrefetchService.swift  # ThumbnailPrefetching protocol + bulk thumbnail download with bounded concurrency, transient retry, and cross-cycle retry cap
├── ViewModels/                         # View state management
│   ├── AddFeedViewModel.swift          # @Observable @MainActor — URL validation + feed subscription via FeedPersisting + icon resolution
│   ├── EditFeedViewModel.swift         # @Observable @MainActor — URL editing + validation + feed update via FeedPersisting
│   ├── ArticleSummaryViewModel.swift   # @Observable @MainActor — extraction state machine
│   ├── DiscussionViewModel.swift       # @Observable @MainActor — chat history + Claude streaming
│   ├── FeedListViewModel.swift         # @Observable @MainActor — feed list management, refresh, OPML, unread counts, icon resolution via FeedPersisting
│   ├── FeedViewModel.swift             # @Observable @MainActor — cached + network article loading, read/unread, sort order, read filter, mark all as read via FeedPersisting
│   └── HomeViewModel.swift             # @Observable @MainActor — total unread count, cross-feed article queries, read/unread, sort order, mark all as read via FeedPersisting
├── Views/                              # SwiftUI views
│   ├── ActivityShareView.swift          # UIViewControllerRepresentable wrapping UIActivityViewController
│   ├── AddFeedView.swift               # Sheet for adding a new feed — URL input + validation
│   ├── AllArticlesView.swift           # Flat chronological list of all articles across all feeds
│   ├── CrossFeedArticleRowView.swift   # Article row with feed name label for cross-feed lists
│   ├── EditFeedView.swift              # Sheet for editing a feed URL — pre-populated input + validation
│   ├── APIKeySettingsView.swift        # Keychain API key entry/removal UI (pushed from SettingsView or presented as sheet)
│   ├── ArticleDiscussionView.swift     # Chat sheet — message bubbles + streaming input
│   ├── ArticleListView.swift           # Feed article list with loading/error/content states
│   ├── ArticleReaderView.swift         # Full-screen reader — WKWebView + AI sparkles toolbar (API key → summary, no key → API key settings)
│   ├── ArticleReaderWebView.swift      # UIViewRepresentable wrapping WKWebView with DOM serializer injection
│   ├── ArticleRowView.swift            # Single article row — thumbnail, title, snippet, date, read/unread styling
│   ├── ArticleThumbnailView.swift     # Article thumbnail display — loads cached JPEG from disk, fallback photo placeholder
│   ├── ArticleSummaryView.swift        # Extracted article summary sheet — extracted content + discuss
│   ├── ContentView.swift               # Root view — creates SwiftDataFeedPersistenceService from modelContext, hosts HomeView
│   ├── FeedIconView.swift              # Feed icon display — loads cached PNG from disk, fallback globe placeholder
│   ├── FeedListView.swift              # Subscribed feed list — NavigationStack root with add/remove, settings gear, unread badges
│   ├── HomeView.swift                  # Home screen — NavigationStack root with All Articles, Unread Articles, All Feeds rows
│   ├── FeedRowView.swift               # Single feed row — icon, title, description, unread count badge
│   ├── SettingsView.swift              # Top-level settings page with NavigationLink rows pushing API Key and Import/Export sub-screens
│   └── UnreadArticlesView.swift        # Filtered list of unread articles across all feeds
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
│   ├── SwiftDataTestHelpers.swift      # In-memory ModelContainer factory for SwiftData tests
│   ├── TestFixtures.swift              # Sample RSS XML, factory methods for Article/RSSFeed/PersistentFeed/PersistentArticle
│   └── WebViewTestHelpers.swift        # WKWebView-based serialization helpers for integration tests
├── Mocks/
│   ├── MockArticleExtractionService.swift  # ArticleExtracting mock with injectable content/errors
│   ├── MockArticleThumbnailService.swift   # ArticleThumbnailCaching mock with injectable cache results
│   ├── MockClaudeAPIService.swift          # ClaudeAPIServicing mock with injectable chunks/errors
│   ├── MockContentExtractor.swift          # ContentExtracting mock with injectable results
│   ├── MockFeedFetchingService.swift       # FeedFetching mock with injectable results/errors
│   ├── MockFeedIconService.swift          # FeedIconResolving mock with injectable URL/cache results
│   ├── MockFeedPersistenceService.swift    # FeedPersisting mock with in-memory store
│   ├── MockFeedStorageService.swift        # FeedStoring mock with in-memory store (for migration tests)
│   ├── MockKeychainService.swift           # KeychainServicing mock with in-memory store
│   ├── MockOPMLService.swift               # OPMLServing mock with injectable entries/data/errors
│   ├── MockThumbnailPrefetchService.swift  # ThumbnailPrefetching mock with call count tracking
│   └── MockURLSessionBytesProvider.swift   # URLSessionBytesProviding mock with URLProtocol-backed controlled SSE lines
├── Models/
│   ├── ArticleTests.swift              # Article creation, identity, hashable
│   ├── DOMNodeTests.swift              # DOMNode accessors, text/element queries, tree traversal
│   ├── HomeGroupTests.swift            # HomeGroup enum cases, IDs, properties, Hashable conformance
│   └── SubscribedFeedTests.swift       # updatingMetadata preserves identity, does not mutate
├── Services/
│   ├── ArticleThumbnailServiceTests.swift # Thumbnail cache miss, delete safety, filename hashing
│   ├── CandidateScorerTests.swift      # Content node identification, scoring, pruning
│   ├── ClaudeAPIServiceSendMessageTests.swift # sendMessage integration — consecutive decode failure counter, stream completion, SSE routing
│   ├── ClaudeAPIServiceTests.swift     # Request encoding, SSE parsing, error handling
│   ├── ContentAssemblerTests.swift     # HTML/text assembly from DOM subtrees
│   ├── ContentExtractorTests.swift     # End-to-end extraction pipeline, site-specific fallback
│   ├── DOMSerializerTests.swift        # WKWebView integration — JS serialization fidelity
│   ├── ExtractionPipelineTests.swift   # Full pipeline: HTML → WKWebView serialize → Swift extract
│   ├── FeedIconServiceTests.swift      # Icon resolution, caching, HTMLUtilities icon extraction
│   ├── FeedPersistenceServiceTests.swift # SwiftData CRUD, upsert, read/unread, cross-feed queries, content cache, cascade delete, thumbnail tracking, sort order, mark all as read, unread per-feed queries
│   ├── FeedStorageServiceTests.swift   # Save/load roundtrip, add/remove, empty state (legacy UserDefaults)
│   ├── HTMLUtilitiesTests.swift        # Tag stripping, entity decoding, image extraction, og:image extraction
│   ├── UserDefaultsMigrationTests.swift # Migration from UserDefaults to SwiftData, idempotency, ID preservation
│   ├── KeychainServiceTests.swift      # Save/load/delete/overwrite roundtrips
│   ├── OPMLServiceTests.swift          # Parse flat/nested/empty OPML, generate + round-trip, XML escaping
│   ├── MetadataExtractorTests.swift    # Title/byline extraction from meta tags and DOM
│   ├── ModelConfigurationValidationTests.swift # ModelValidation and MaxTokensValidation input validation
│   ├── RSSParsingServiceTests.swift    # Channel parsing, thumbnails, IDs, edge cases
│   └── ThumbnailPrefetchServiceTests.swift # Bulk prefetch, skip cached/maxed, retry count, mixed results, error handling
├── ViewModels/
│   ├── AddFeedViewModelTests.swift         # URL validation, duplicate detection, success/failure
│   ├── EditFeedViewModelTests.swift        # URL editing, validation, duplicate detection, success/failure
│   ├── ArticleReaderViewModelTests.swift   # ArticleSummaryViewModel pre-extraction state tests
│   ├── DiscussionViewModelTests.swift      # Message flow, streaming, no-key behavior
│   ├── FeedListViewModelTests.swift        # Load, remove by object, remove by IndexSet
│   ├── FeedViewModelTests.swift            # Load success/failure, state transitions, sort order, read filter, mark all as read
│   └── HomeViewModelTests.swift            # Unread count, cross-feed article queries, read/unread status, sort order, mark all as read
```

**Total: 63 source files + 1 resource, 48 test source files + 1 fixture.**

## Key Components

The directory tree annotations describe each file's purpose. This section covers cross-cutting flows and relationships that aren't obvious from individual files.

**Native content extraction pipeline.** `ArticleExtractionService` (`@MainActor`) loads the article URL in a hidden 1×1 `WKWebView`, injects `domSerializer.js` (which serializes the DOM tree to JSON), and bridges the result into Swift via `evaluateJavaScript` using `withCheckedThrowingContinuation` + `WKNavigationDelegate` with a 35-second safety timeout. `DOMSerializerConstants` shares the JS bridge constants (`messageHandlerName`, `serializerCall`) between `ArticleExtractionService` and `ArticleReaderWebView`. `ContentExtractor` (`ContentExtracting` protocol) orchestrates the Swift-side pipeline: `SiteSpecificExtracting` per-hostname extractors (checked first) → `MetadataExtractor` (title/byline from OpenGraph/article meta tags and DOM elements like `<h1>`, byline class patterns) → `CandidateScorer` (Readability-style algorithm that prunes unlikely nodes like nav/sidebar/footer, scores paragraphs and propagates to ancestors with decay, penalizes high link-density nodes) → `ContentAssembler` (produces clean `htmlContent` preserving semantic tags and `textContent` with paragraph breaks from the winning subtree). `CandidateScorer` internally wraps `DOMNode` values in reference-type `NodeWrapper` to add parent pointers during scoring. Falls back to the RSS `articleDescription` if extraction fails.

**SwiftData persistence model.** `PersistentFeed` → `@Relationship(deleteRule: .cascade)` → `[PersistentArticle]` → `@Relationship(deleteRule: .cascade)` → optional `PersistentArticleContent`. All `@Model` properties use optionals or defaults for future CloudKit compatibility. `ModelConversion` provides bidirectional conversion extensions: `PersistentFeed` ↔ `SubscribedFeed`, `PersistentArticle` ↔ `Article`, `PersistentArticleContent` ↔ `ArticleContent`. Transient parser structs (`Article`, `RSSFeed`, `ArticleContent`) remain as transfer objects from the RSS parser and content extractor. `FeedPersisting` (`@MainActor` protocol) defines the persistence API; `SwiftDataFeedPersistenceService` implements it with feed CRUD, article upsert (deduplicating by `articleID` within a feed, preserving read status), content caching, paginated queries via `FetchDescriptor.fetchOffset`/`fetchLimit` with configurable sort order (`ascending` parameter), per-feed unread article queries, and bulk `markAllArticlesRead()` / `markAllArticlesRead(for:)` operations.

**Cache-first loading (`FeedViewModel`).** On `loadFeed()`, displays the first page of cached `[PersistentArticle]` immediately (page size 50), then fetches from network and upserts new articles, reloading up to `max(articles.count, pageSize)` to preserve scroll position. `loadMoreArticles()` provides infinite scroll with deduplication and error-stop (`hasMore` set to `false` on error). Loading spinner only shown when no cached articles; error only shown when network fails and no cached articles (offline resilience). Pagination errors surface via `.alert` when articles are already loaded. Supports a `showUnreadOnly` toggle (per-feed filter) and a global `sortAscending` preference (persisted in UserDefaults under `articleSortAscending`, shared between `FeedViewModel` and `HomeViewModel`). `markAllAsRead()` bulk-marks all articles in the feed as read via the persistence layer.

**Claude API streaming flow.** `KeychainService` (`KeychainServicing` protocol, wraps `Security` framework `kSecClassGenericPassword`) loads the Anthropic API key → `ClaudeAPIService` (`ClaudeAPIServicing` protocol) POSTs to the Messages API with `stream: true`, reads SSE lines via `URLSessionBytesProviding` (injectable, defaults to `URLSession.shared`), yields text deltas via `AsyncThrowingStream<String, Error>` → `DiscussionViewModel` appends user turn, creates empty assistant placeholder, then streams chunks into `messages[lastIndex].content`. Model identifier and max output tokens read from `UserDefaults` at call time (keys: `claude_model_identifier`, `claude_max_tokens`) with fallback defaults (`claude-haiku-4-5-20251001`, `4096`).

**OPML import pipeline.** `OPMLService` (`OPMLServing` protocol) parses OPML via `XMLParser` with a private `OPMLParserDelegate` that captures all `<outline>` elements with `xmlUrl` attributes regardless of nesting depth (flattening folders), accepting outlines without `type="rss"` for compatibility. Result is `[OPMLFeedEntry]` (intermediate type decoupled from persistence — lacks `id`/`addedDate`). `FeedListViewModel.importOPML(from:)` deduplicates via `FeedPersisting.feedExists(url:)` and calls `addFeed` for new entries. `importOPMLAndRefresh(from:)` extends this by fetching each feed's RSS XML to populate metadata. Export converts `PersistentFeed` → `SubscribedFeed` via `ModelConversion` for OPML generation.

**UserDefaults → SwiftData migration.** `UserDefaultsMigrationService` reads the legacy `SubscribedFeed` list from UserDefaults via `FeedStoring` (`FeedStorageService`), converts to `PersistentFeed` records preserving IDs. One-time and idempotent — sets a migration flag on success, retries on failure. Skipped in test environments (detected via `XCTestConfigurationFilePath`, uses in-memory store).

**Feed icon resolution chain.** `FeedIconService` (`FeedIconResolving` protocol) resolves via priority chain: feed XML image URL → site homepage HTML meta tags (apple-touch-icon, `link rel="icon"`) → `/favicon.ico` fallback. Downloads the resolved image, normalizes to PNG (resizing if larger than 128px), and caches to `{cachesDirectory}/feed-icons/{feedID}.png`. `FeedIconView` loads cached PNG from disk with globe placeholder fallback. Resolution triggered by `FeedListViewModel` during refresh and `AddFeedViewModel` during feed add.

**Article thumbnail resolution and prefetch.** `ArticleThumbnailService` (`ArticleThumbnailCaching` protocol) resolves via: direct thumbnail URL from the feed → `og:image` meta tag from the article's web page (via `HTMLUtilities.extractOGImageURL`). Resizes to 120×120px (aspect-fill + center-crop), caches as JPEG to `{cachesDirectory}/article-thumbnails/{SHA256(articleID)}.jpg`. `ThumbnailPrefetchService` (`ThumbnailPrefetching` protocol) eagerly downloads thumbnails during feed refresh: queries `PersistentArticle` records where `isThumbnailCached == false && thumbnailRetryCount < maxRetryCount`, downloads up to 4 thumbnails concurrently, retries transient failures within a cycle with exponential backoff, and increments `thumbnailRetryCount` on failure so broken URLs stop retrying after the cap (3 attempts). Kicked off by `FeedListViewModel.refreshAllFeeds()` as a background `Task(priority: .utility)` after feed save. `ArticleThumbnailView` reads from disk cache first; on-demand resolution is retained as fallback for articles predating the prefetch feature or whose prefetch is still in progress.

## Data Flow

```
RSSAppApp (@main)
  ├── ModelContainer (PersistentFeed, PersistentArticle, PersistentArticleContent)
  ├── UserDefaultsMigrationService → one-time migration from UserDefaults
  └── WindowGroup (.modelContainer)
      └── ContentView (@Environment modelContext → SwiftDataFeedPersistenceService)
          └── HomeView (NavigationStack root, HomeViewModel)
              ├── AllArticlesView (paginated cross-feed list, HomeViewModel)
              ├── UnreadArticlesView (filtered unread list, HomeViewModel)
              └── FeedListView (FeedListViewModel + FeedPersisting/OPMLServing/FeedFetching/FeedIconResolving)
                  └── ArticleListView (FeedViewModel per feed, cache-first loading)
                      └── ArticleReaderView (WKWebView + domSerializer.js early extraction)
                          └── ArticleSummaryView (ArticleSummaryViewModel + ArticleExtractionService)
                              └── ArticleDiscussionView (DiscussionViewModel + ClaudeAPIService + KeychainService)
```

**Observation pattern:** SwiftUI views observe `@Observable @MainActor` view models. View models delegate to protocol-abstracted services (`FeedPersisting`, `FeedFetching`, `FeedIconResolving`, `ArticleThumbnailCaching`, `ThumbnailPrefetching`, `OPMLServing`, `ClaudeAPIServicing`, `KeychainServicing`, `ArticleExtracting`, `ContentExtracting`), enabling mock injection for testing.

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
| SwiftData for persistence | Replaced UserDefaults; supports relational model (feeds → articles → content), read/unread tracking, offline article caching, and future CloudKit sync |
| `@MainActor` persistence service (not `ModelActor`) | Matches view model `@MainActor` isolation; avoids non-`Sendable` `@Model` cross-actor transfer issues; small data volume makes main-thread DB access acceptable |
| Transient parser structs retained alongside `@Model` classes | RSS parser and content extractor produce `Article`/`RSSFeed`/`ArticleContent` structs; these remain as transfer objects with `ModelConversion` extensions bridging to `@Model` persistence layer |
| CloudKit-ready model design | All `@Model` properties use optionals or defaults; no code change needed when enabling sync later |
| Article deduplication by `(articleID, feed)` | Same article ID can exist across different feeds; upsert preserves read status on existing articles |
| `SubscribedFeed` retained for migration and OPML | `UserDefaultsMigrationService` reads legacy `Codable` data; `OPMLService` generates OPML from `SubscribedFeed` structs via conversion |
| `OPMLFeedEntry` intermediate type | Decouples OPML parser from persistence model; OPML data lacks `id`/`addedDate` fields |
| Manual XML generation for OPML export | `XMLDocument` is macOS-only; string building with XML escaping is sufficient for the simple OPML structure |
| OPML import accepts outlines without `type="rss"` | Real-world OPML files often omit the type attribute; any outline with a valid `xmlUrl` is treated as a feed |
| Feed title fetched at add-time | Validates the URL is a real feed; better UX than requiring manual title entry |
| `FeedViewModel` with cache-first loading | Shows cached articles immediately from SwiftData, then fetches from network and upserts; enables offline browsing |
| Home screen as app root | Provides meta-groups (All Articles, Unread Articles, All Feeds) above the feed list; pushes `FeedListView` via NavigationStack rather than replacing it |
| `HomeGroup` enum for group types | Three fixed cases with `CaseIterable`; enum-based approach accommodates future user-created groups (folders, tags) by adding new cases |
| Cross-feed article queries in `FeedPersisting` | `allArticles()`, `allUnreadArticles()`, `totalUnreadCount()` are protocol methods so they work with both SwiftData and mock implementations |
| Offset-based pagination (page size 50) | Simple `fetchOffset`/`fetchLimit` on `FetchDescriptor`; deduplication filter on append prevents duplicates from dataset shifts; `hasMore` flag set to `false` on error to prevent infinite retry loops; previous list preserved on reload failure |
| Stable list snapshot | Article lists capture a snapshot on load and do not re-query when individual read states change; visual indicators update in-place via SwiftData `@Model` observation; lists re-query only on explicit triggers (pull-to-refresh, navigation return, sort/filter change, mark all as read) |
| Global sort order in UserDefaults | Single `articleSortAscending` key shared between `FeedViewModel` and `HomeViewModel`; changing the preference triggers an immediate reload of the current article list |
| Article list toolbar menu | `ellipsis.circle` menu on all article list views; sort order + mark all as read on all views; read/unread filter only on `ArticleListView` (per-feed) since `AllArticlesView` and `UnreadArticlesView` have fixed scope |
| Confirmation dialog for mark all as read | Destructive bulk operation always requires user confirmation regardless of view |

## Test Coverage

**48 test files: 31 test suites, 12 mock implementations, 4 shared helpers, 1 HTML fixture.**

**Patterns:** Swift Testing (`@Suite`, `@Test`, `#expect`). Protocol-based dependency injection with 12 mocks (`MockFeedPersistenceService`, `MockFeedFetchingService`, `MockFeedIconService`, `MockArticleThumbnailService`, `MockThumbnailPrefetchService`, `MockOPMLService`, `MockClaudeAPIService`, `MockKeychainService`, `MockArticleExtractionService`, `MockContentExtractor`, `MockFeedStorageService`, `MockURLSessionBytesProvider`). In-memory `ModelContainer` via `SwiftDataTestHelpers` for SwiftData integration tests. `WKWebView` integration tests via `WebViewTestHelpers` for DOM serialization and extraction pipeline. `MockURLSessionBytesProvider` with `URLProtocol` interception for `ClaudeAPIService.sendMessage` integration tests. Shared `TestFixtures` factory methods for `Article`, `RSSFeed`, `PersistentFeed`, `PersistentArticle`, and sample RSS XML.

**Well-covered:** All models, services, and view models have test suites with mock injection — including happy paths, error paths, edge cases, and state transitions.

**Not tested:** SwiftUI views and the `@main` app entry point (no UI tests).
