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
│   ├── ClaudeAPIService.swift          # Claude API client — streaming SSE via URLSession
│   ├── ContentAssembler.swift          # Reconstructs clean HTML + plain text from winning DOM subtree
│   ├── ContentExtractor.swift          # ContentExtracting protocol + extraction pipeline orchestrator
│   ├── DOMSerializerConstants.swift    # Shared JS bridge constants (message handler name, serializer call)
│   ├── FeedFetchingService.swift       # FeedFetching protocol + URLSession implementation
│   ├── ArticleThumbnailService.swift   # ArticleThumbnailCaching protocol + thumbnail download, resize-to-120px, JPEG disk caching
│   ├── FeedIconService.swift           # FeedIconResolving protocol + icon URL resolution (feed XML → site HTML → /favicon.ico) and file-system caching
│   ├── FeedPersistenceService.swift    # FeedPersisting protocol + SwiftData implementation (feeds, articles, content cache, read/unread)
│   ├── FeedStorageService.swift        # FeedStoring protocol + UserDefaults persistence — retained for migration only
│   ├── FeedURLValidator.swift          # Shared URL normalization + validation (trim, scheme prepend, HTTP/HTTPS + host check)
│   ├── UserDefaultsMigrationService.swift # One-time migration from UserDefaults SubscribedFeed list to SwiftData PersistentFeed
│   ├── HTMLUtilities.swift             # HTML/XML escaping (text + attributes), tag stripping, entity decoding, image extraction, og:image extraction, icon URL extraction
│   ├── KeychainService.swift           # Keychain wrapper for secure API key storage
│   ├── MetadataExtractor.swift         # Extracts article title/byline from meta tags and DOM elements
│   ├── ModelConfigurationValidator.swift # ModelValidation + MaxTokensValidation enums — input validation for model ID and max tokens
│   ├── OPMLService.swift               # OPMLServing protocol + XMLParser-based OPML parser + XML generator
│   ├── RSSParsingService.swift         # XMLParser-based RSS 2.0 + Atom parser with XHTML content reconstruction
│   └── SiteSpecificExtracting.swift    # Protocol for per-hostname content extractors
├── ViewModels/                         # View state management
│   ├── AddFeedViewModel.swift          # @Observable @MainActor — URL validation + feed subscription via FeedPersisting + icon resolution
│   ├── EditFeedViewModel.swift         # @Observable @MainActor — URL editing + validation + feed update via FeedPersisting
│   ├── ArticleSummaryViewModel.swift   # @Observable @MainActor — extraction state machine
│   ├── DiscussionViewModel.swift       # @Observable @MainActor — chat history + Claude streaming
│   ├── FeedListViewModel.swift         # @Observable @MainActor — feed list management, refresh, OPML, unread counts, icon resolution via FeedPersisting
│   └── FeedViewModel.swift             # @Observable @MainActor — cached + network article loading, read/unread via FeedPersisting
├── Views/                              # SwiftUI views
│   ├── ActivityShareView.swift          # UIViewControllerRepresentable wrapping UIActivityViewController
│   ├── AddFeedView.swift               # Sheet for adding a new feed — URL input + validation
│   ├── EditFeedView.swift              # Sheet for editing a feed URL — pre-populated input + validation
│   ├── APIKeySettingsView.swift        # Keychain API key entry/removal UI (pushed from SettingsView or presented as sheet)
│   ├── ArticleDiscussionView.swift     # Chat sheet — message bubbles + streaming input
│   ├── ArticleListView.swift           # Feed article list with loading/error/content states
│   ├── ArticleReaderView.swift         # Full-screen reader — WKWebView + AI sparkles toolbar (API key → summary, no key → API key settings)
│   ├── ArticleReaderWebView.swift      # UIViewRepresentable wrapping WKWebView with DOM serializer injection
│   ├── ArticleRowView.swift            # Single article row — thumbnail, title, snippet, date, read/unread styling
│   ├── ArticleThumbnailView.swift     # Article thumbnail display — loads cached JPEG from disk, fallback photo placeholder
│   ├── ArticleSummaryView.swift        # Extracted article summary sheet — extracted content + discuss
│   ├── ContentView.swift               # Root view — creates SwiftDataFeedPersistenceService from modelContext, hosts FeedListView
│   ├── FeedIconView.swift              # Feed icon display — loads cached PNG from disk, fallback globe placeholder
│   ├── FeedListView.swift              # Subscribed feed list — NavigationStack root with add/remove, settings gear, unread badges
│   ├── FeedRowView.swift               # Single feed row — icon, title, description, unread count badge
│   └── SettingsView.swift              # Top-level settings page with NavigationLink rows pushing API Key and Import/Export sub-screens
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
│   └── MockOPMLService.swift               # OPMLServing mock with injectable entries/data/errors
├── Models/
│   ├── ArticleTests.swift              # Article creation, identity, hashable
│   ├── DOMNodeTests.swift              # DOMNode accessors, text/element queries, tree traversal
│   └── SubscribedFeedTests.swift       # updatingMetadata preserves identity, does not mutate
├── Services/
│   ├── ArticleThumbnailServiceTests.swift # Thumbnail cache miss, delete safety, filename hashing
│   ├── CandidateScorerTests.swift      # Content node identification, scoring, pruning
│   ├── ClaudeAPIServiceTests.swift     # Request encoding, SSE parsing, error handling
│   ├── ContentAssemblerTests.swift     # HTML/text assembly from DOM subtrees
│   ├── ContentExtractorTests.swift     # End-to-end extraction pipeline, site-specific fallback
│   ├── DOMSerializerTests.swift        # WKWebView integration — JS serialization fidelity
│   ├── ExtractionPipelineTests.swift   # Full pipeline: HTML → WKWebView serialize → Swift extract
│   ├── FeedIconServiceTests.swift      # Icon resolution, caching, HTMLUtilities icon extraction
│   ├── FeedPersistenceServiceTests.swift # SwiftData CRUD, upsert, read/unread, content cache, cascade delete
│   ├── FeedStorageServiceTests.swift   # Save/load roundtrip, add/remove, empty state (legacy UserDefaults)
│   ├── HTMLUtilitiesTests.swift        # Tag stripping, entity decoding, image extraction, og:image extraction
│   ├── UserDefaultsMigrationTests.swift # Migration from UserDefaults to SwiftData, idempotency, ID preservation
│   ├── KeychainServiceTests.swift      # Save/load/delete/overwrite roundtrips
│   ├── OPMLServiceTests.swift          # Parse flat/nested/empty OPML, generate + round-trip, XML escaping
│   ├── MetadataExtractorTests.swift    # Title/byline extraction from meta tags and DOM
│   ├── ModelConfigurationValidationTests.swift # ModelValidation and MaxTokensValidation input validation
│   └── RSSParsingServiceTests.swift    # Channel parsing, thumbnails, IDs, edge cases
├── ViewModels/
│   ├── AddFeedViewModelTests.swift         # URL validation, duplicate detection, success/failure
│   ├── EditFeedViewModelTests.swift        # URL editing, validation, duplicate detection, success/failure
│   ├── ArticleReaderViewModelTests.swift   # ArticleSummaryViewModel pre-extraction state tests
│   ├── DiscussionViewModelTests.swift      # Message flow, streaming, no-key behavior
│   ├── FeedListViewModelTests.swift        # Load, remove by object, remove by IndexSet
│   └── FeedViewModelTests.swift            # Load success/failure, state transitions
```

**Total: 56 source files + 1 resource, 42 test source files + 1 fixture.**

## Component Map

### App Layer

**Files:** `RSSAppApp.swift`

`RSSAppApp` is the entry point. It creates a `ModelContainer` for the SwiftData schema (`PersistentFeed`, `PersistentArticle`, `PersistentArticleContent`), runs `UserDefaultsMigrationService` on first launch to migrate legacy data, and declares a `WindowGroup` scene with `.modelContainer()` containing `ContentView`. In test environments (detected via `XCTestConfigurationFilePath`), uses an in-memory store and skips migration. The app uses the SwiftUI App lifecycle — no `AppDelegate` or `SceneDelegate`.

### Models

**Files:** `Article.swift`, `ArticleContent.swift`, `ChatMessage.swift`, `DOMNode.swift`, `ModelConversion.swift`, `OPMLFeedEntry.swift`, `OPMLImportResult.swift`, `PersistentArticle.swift`, `PersistentArticleContent.swift`, `PersistentFeed.swift`, `RSSFeed.swift`, `SubscribedFeed.swift`

**SwiftData persistence models** — Three `@Model` classes form the persistence layer with relationships:

`PersistentFeed` stores feed subscriptions: id, title, feedURL, description, addedDate, caching headers (etag, lastModifiedHeader, lastRefreshDate), icon URL (iconURL), and error state (lastFetchError, lastFetchErrorDate). Has a `@Relationship(deleteRule: .cascade)` to `[PersistentArticle]`. All properties use optionals or defaults for future CloudKit compatibility.

`PersistentArticle` stores article data: articleID (RSS guid/Atom id), title, link, description, snippet, publishedDate, thumbnailURL, author, categories, read status (isRead, readDate), and fetchedDate. Has a relationship to `PersistentFeed` and a `@Relationship(deleteRule: .cascade)` to optional `PersistentArticleContent`.

`PersistentArticleContent` caches extracted article content: title, byline, htmlContent, textContent, and extractedDate. Has a relationship to `PersistentArticle`.

`ModelConversion` provides bidirectional conversion extensions between the `@Model` classes and the transient parser structs: `PersistentFeed` ↔ `SubscribedFeed`, `PersistentArticle` ↔ `Article`, `PersistentArticleContent` ↔ `ArticleContent`.

**Transient parser structs** — These remain as transfer objects from the RSS parser and content extractor:

`Article` represents a single feed item parsed from RSS/Atom XML. Conforms to `Identifiable`, `Hashable`, and `Sendable`.

`ArticleContent` holds the result of content extraction: `htmlContent` (clean HTML for display) and `textContent` (plain text for AI context), plus `title` and `byline`. Has a static `rssFallback(html:)` factory for graceful degradation.

`RSSFeed` represents a parsed feed channel — title, link, description, an array of `Article` values, an optional `lastUpdated` date, and an optional `imageURL` (extracted from RSS `<image>`, Atom `<logo>`, or Atom `<icon>`). Also `Sendable`.

`SubscribedFeed` is the legacy feed subscription struct retained for UserDefaults migration (`UserDefaultsMigrationService`) and OPML export compatibility. Conforms to `Codable`.

**Other models:**

`ChatMessage` represents a single turn in the discussion chat. `role` is `.user` or `.assistant`. `content` is mutable (`var`) to allow streaming chunks to be appended in place.

`DOMNode.swift` defines `SerializedDOM` (top-level page representation with title, URL, lang, meta tags, and body tree) and `DOMNode` (recursive tree node with tag name, attributes, visibility flag, and children). Both are `Codable` and `Sendable` value types. `CandidateScorer` internally wraps nodes in a reference-type `NodeWrapper` to add parent pointers during scoring.

`OPMLFeedEntry` is an intermediate type for parsed OPML feed entries — title, feed URL, optional site URL, and description. Decoupled from persistence because OPML data lacks `id` and `addedDate`.

`OPMLImportResult` communicates import outcome to the UI — counts of added, skipped, and total feeds in the file.

### Services

**Files:** `ArticleExtractionService.swift`, `ArticleThumbnailService.swift`, `CandidateScorer.swift`, `ClaudeAPIService.swift`, `ContentAssembler.swift`, `ContentExtractor.swift`, `DOMSerializerConstants.swift`, `FeedFetchingService.swift`, `FeedIconService.swift`, `FeedPersistenceService.swift`, `FeedStorageService.swift`, `FeedURLValidator.swift`, `HTMLUtilities.swift`, `KeychainService.swift`, `MetadataExtractor.swift`, `OPMLService.swift`, `RSSParsingService.swift`, `SiteSpecificExtracting.swift`

`FeedFetching` is a protocol defining `fetchFeed(from:) async throws -> RSSFeed`. `FeedFetchingService` fetches data via `URLSession.shared` and delegates parsing to `RSSParsingService`.

`RSSParsingService` wraps Foundation's `XMLParser` to parse both RSS 2.0 and Atom feeds with first-class support for each format. Handles Atom XHTML content reconstruction (serializing inner XML back to HTML when `type="xhtml"`), author extraction (RSS `<author>` text and Atom `<author><name>` nesting), categories (RSS `<category>` text and Atom `<category term>` attributes), Atom `<link rel="enclosure">` for media, feed-level updated dates, and channel-level image URLs (RSS `<image><url>`, Atom `<logo>`, Atom `<icon>`). Internally uses a synchronous `XMLParserDelegate` class marked `@unchecked Sendable` (safe because it is created and consumed within a single synchronous `parse()` call).

`FeedIconResolving` is a `Sendable` protocol. `FeedIconService` resolves feed icon URLs through a multi-step priority chain: feed XML image URL → site homepage HTML meta tags (apple-touch-icon, link rel="icon") → `/favicon.ico` fallback. Downloads the resolved image, normalizes it to PNG (resizing if larger than 128px), and caches it to the file system at `{cachesDirectory}/feed-icons/{feedID}.png`. Provides cache lookup and cleanup methods. Used by `FeedListViewModel` during refresh and `AddFeedViewModel` during feed add.

`ArticleThumbnailCaching` is a `Sendable` protocol. `ArticleThumbnailService` downloads article thumbnail images, resizes them to 120×120px (aspect-fill + center-crop), and caches them as JPEG to `{cachesDirectory}/article-thumbnails/{SHA256(articleID)}.jpg`. Uses a two-step resolution: direct thumbnail URL from the feed → `og:image` meta tag from the article's web page (for feeds like TechCrunch that don't include images in RSS). `ArticleThumbnailView` resolves and caches thumbnails on-demand off the main thread, with self-healing for corrupt cache entries.

`HTMLUtilities` provides static methods for stripping HTML tags/entities to plain text, escaping special characters in HTML text content and attribute values, extracting the first `<img>` URL, extracting `og:image` URLs from `<meta property="og:image">` tags (used by `ArticleThumbnailService`), and extracting icon/favicon URLs from HTML `<link>` and `<meta>` tags (used by `FeedIconService`).

**Native content extraction pipeline:** The app uses a custom Swift-native extraction pipeline (replacing Readability.js as of PR #3). The pipeline consists of:

- `ArticleExtractionService` — `@MainActor` service that loads the article URL in a hidden 1×1 `WKWebView`, injects `domSerializer.js` (which serializes the DOM tree to JSON), and bridges the result into Swift via `evaluateJavaScript`. Uses `withCheckedThrowingContinuation` + `WKNavigationDelegate` with a 35-second safety timeout. Falls back to the RSS `articleDescription` if extraction fails.
- `DOMSerializerConstants` — shared enum with the JS bridge constants (`messageHandlerName`, `serializerCall`) used by both `ArticleExtractionService` and `ArticleReaderWebView`.
- `ContentExtractor` — orchestrates the extraction pipeline: site-specific extractors → metadata extraction → candidate scoring → content assembly. Conforms to `ContentExtracting` protocol for testability.
- `CandidateScorer` — Readability-style algorithm that scores DOM nodes to find the article content container. Prunes unlikely nodes (nav, sidebar, footer), scores paragraphs and propagates to ancestors with decay, penalizes high link-density nodes.
- `ContentAssembler` — walks the winning DOM subtree and produces clean `htmlContent` (preserving semantic tags) and `textContent` (plain text with paragraph breaks).
- `MetadataExtractor` — extracts article title and byline from OpenGraph/article meta tags and DOM elements (`<h1>`, byline class patterns).
- `SiteSpecificExtracting` — extensibility protocol for per-hostname extractors. Implementations are checked before the generic algorithm runs.

`ClaudeAPIServicing` is a `Sendable` protocol. `ClaudeAPIService` POSTs to the Anthropic Messages API with `stream: true`, reads SSE lines via `URLSession.bytes(for:).lines`, and yields text deltas via `AsyncThrowingStream<String, Error>`. Model identifier and max output tokens are read from `UserDefaults` at call time (keys: `claude_model_identifier`, `claude_max_tokens`) with fallback defaults (`claude-haiku-4-5-20251001`, `4096`), so changes in settings take effect on the next API call without restarting. Accepts a `UserDefaults` parameter for testability.

`KeychainServicing` is a `Sendable` protocol. `KeychainService` wraps `Security` framework (`kSecClassGenericPassword`) to save, load, and delete the Anthropic API key. The key is stored encrypted by the OS and never touches any file accessible to git.

`FeedURLValidator` is a shared utility enum that normalizes and validates raw URL input strings. It trims whitespace, prepends `https://` when no scheme is present, and validates the result has an HTTP or HTTPS scheme with a non-nil host. Used by both `AddFeedViewModel` and `EditFeedViewModel` to deduplicate URL validation logic.

`FeedPersisting` is a `@MainActor` protocol defining the persistence layer. `SwiftDataFeedPersistenceService` implements it using a `ModelContext`. Provides feed CRUD, article upsert (deduplicating by `articleID` within a feed, preserving read status), read/unread tracking, unread counts, and content caching. The `@MainActor` isolation matches the view model pattern and avoids `@Model` cross-actor transfer issues.

`UserDefaultsMigrationService` performs a one-time migration of `SubscribedFeed` data from UserDefaults to SwiftData on first launch. Idempotent — sets a migration flag on success and retries on failure.

`FeedStoring` is a `Sendable` protocol retained for migration support only. `FeedStorageService` reads the legacy `UserDefaults` feed list for `UserDefaultsMigrationService`. No view models depend on it.

`OPMLServing` is a `Sendable` protocol. `OPMLService` handles OPML import/export. Parsing uses `XMLParser` with a private `OPMLParserDelegate` (same `@unchecked Sendable` pattern as `RSSParserDelegate`) that captures all `<outline>` elements with `xmlUrl` attributes regardless of nesting depth, flattening folders. Generation builds OPML 2.0 XML with proper XML escaping. Accepts outlines regardless of `type` attribute for maximum compatibility with real-world OPML files.

### ViewModels

**Files:** `AddFeedViewModel.swift`, `ArticleSummaryViewModel.swift`, `DiscussionViewModel.swift`, `EditFeedViewModel.swift`, `FeedListViewModel.swift`, `FeedViewModel.swift`

All view models are `@MainActor @Observable`.

`FeedListViewModel` manages the subscribed feed list via `FeedPersisting`. Loads `[PersistentFeed]` from the database, supports removal by object or `IndexSet` (with icon cache cleanup), provides `unreadCount(for:)` per feed, and handles OPML import/export via `OPMLServing`. `importOPML(from:)` parses OPML data, deduplicates via `feedExists(url:)`, and adds new `PersistentFeed` objects. `importOPMLAndRefresh(from:)` extends import by fetching each feed's RSS XML to populate metadata. `exportOPML()` converts `PersistentFeed` to `SubscribedFeed` for OPML generation. `refreshAllFeeds()` re-fetches RSS metadata for all subscribed feeds concurrently (max 6 in-flight), upserts articles into the database, updates feed metadata/error state, and resolves/caches feed icons for feeds without a cached icon. Accepts `FeedPersisting`, `OPMLServing`, `FeedFetching`, and `FeedIconResolving` dependencies for testability.

`AddFeedViewModel` handles the add-feed flow: URL input, validation (scheme/host check, duplicate detection via `feedExists`), fetching the feed to extract its title, creating a `PersistentFeed` via `FeedPersisting`, and fire-and-forget icon resolution. Accepts `FeedFetching`, `FeedPersisting`, and `FeedIconResolving` dependencies for testability.

`EditFeedViewModel` handles the edit-feed flow: pre-populated URL input, validation (duplicate detection via `feedExists`), fetching the new URL, and updating the `PersistentFeed` via `FeedPersisting`. Clears error state on successful URL change. Accepts `FeedFetching` and `FeedPersisting` dependencies for testability.

`FeedViewModel` manages the article list for a single feed. Takes a `PersistentFeed` and `FeedPersisting`. On `loadFeed()`, displays cached `[PersistentArticle]` immediately, then fetches from network and upserts new articles. Provides `markAsRead(_:)` and `toggleReadStatus(_:)` for read/unread tracking. Only shows loading spinner when there are no cached articles. Only shows error when network fails and there are no cached articles (offline resilience).

`ArticleSummaryViewModel` drives the article summary/extraction flow. Its `State` enum (`idle` / `extracting` / `ready(ArticleContent)` / `failed(String)`) reflects the extraction lifecycle. Stores `extractedContent` for use by the discussion sheet. Accepts an `ArticleExtracting` dependency for testability.

`DiscussionViewModel` manages the chat session. `sendMessage()` appends the user turn, appends an empty assistant placeholder, then streams Claude API response chunks into `messages[lastIndex].content`. Reads the API key from `KeychainServicing`. Accepts both `ClaudeAPIServicing` and `KeychainServicing` dependencies for testability.

### Views

**Files:** `ActivityShareView.swift`, `AddFeedView.swift`, `APIKeySettingsView.swift`, `ArticleDiscussionView.swift`, `ArticleListView.swift`, `ArticleReaderView.swift`, `ArticleReaderWebView.swift`, `ArticleRowView.swift`, `ArticleSummaryView.swift`, `ArticleThumbnailView.swift`, `ContentView.swift`, `FeedIconView.swift`, `FeedListView.swift`, `FeedRowView.swift`, `SettingsView.swift`

`ContentView` creates a `SwiftDataFeedPersistenceService` from the `@Environment(\.modelContext)` and passes it to `FeedListView`.

`FeedListView` is the `NavigationStack` root. Accepts a `FeedPersisting` instance and creates `FeedListViewModel`. Shows the list of subscribed feeds using `FeedRowView` rows with `NavigationLink(value: PersistentFeed.id)`. Empty state shows a `ContentUnavailableView` prompting the user to add a feed. Toolbar has add (+) and a settings gear icon that pushes `SettingsView` via NavigationStack. Uses `.navigationDestination(for: UUID.self)` to push `ArticleListView` with a `FeedViewModel` for the selected feed. Supports swipe-to-delete, swipe-to-edit, and pull-to-refresh to update feed metadata and upsert articles. Passes the persistence service to `AddFeedView` and `EditFeedView`.

`ActivityShareView` is a `UIViewControllerRepresentable` wrapping `UIActivityViewController` for sharing exported OPML files.

`FeedRowView` displays a `PersistentFeed`'s title (`.headline`), description (`.subheadline`, `.secondary`), an error indicator when `lastFetchError` is non-nil, and an unread count badge (blue capsule) when `unreadCount > 0`.

`AddFeedView` is a sheet accepting a `FeedPersisting` instance. Shows a `Form` for entering a feed URL with validation progress and error states. Auto-dismisses on successful addition.

`EditFeedView` is a sheet accepting a `PersistentFeed` and `FeedPersisting`. Pre-populates the URL field, validates the new URL, fetches the feed to confirm it works, and auto-dismisses on success.

`ArticleListView` shows `[PersistentArticle]` with loading / error / list states. Supports swipe actions to mark articles as read/unread. Tapping a row marks it as read and presents `ArticleReaderView` via `.fullScreenCover`. Uses `viewModel.feedTitle` as the navigation title.

`ArticleRowView` displays a `PersistentArticle` with a 60×60 `AsyncImage` thumbnail, headline title (bold for unread, regular for read), subheadline snippet, and caption-style relative date. Read articles show dimmed (`.secondary`) title text.

`ArticleReaderView` is presented as a `fullScreenCover`. It hosts a `NavigationStack` with Done (dismiss) and sparkles (AI) toolbar buttons. The sparkles button checks for an API key: if configured, it presents `ArticleSummaryView` (for extraction); if not configured, it presents `APIKeySettingsView` as a sheet so the user can discover and enter their key. The discussion flow is reached from within `ArticleSummaryView`. The `ArticleReaderWebView` coordinator performs early extraction via a `WKScriptMessageHandler`, making pre-extracted content available for the summary and discussion flows.

`ArticleReaderWebView` is a `UIViewRepresentable` wrapping `WKWebView`. It injects `domSerializer.js` at document end for early extraction, and its `Coordinator` handles both early extraction (via message handler) and fallback extraction (via `didFinish` delegate). Stores results in a shared `ReaderExtractionState` observable.

`ArticleSummaryView` is a sheet that displays extracted article content (title, byline, text) with a toolbar button to open the discussion. Uses `ArticleSummaryViewModel` for extraction state management.

`ArticleDiscussionView` is a sheet. It shows a `ScrollViewReader`-driven chat list with user (blue, right-aligned) and assistant (grey, left-aligned) message bubbles, and a text input bar. When no API key is configured, a `ContentUnavailableView` prompt replaces the chat.

`SettingsView` is the top-level settings page, pushed from `FeedListView` via the gear toolbar icon using a `NavigationLink` within `FeedListView`'s `NavigationStack`. Contains `NavigationLink` rows for API Key (pushes `APIKeySettingsView`) and Import/Export (pushes `ImportExportView`). `ImportExportView` (defined in the same file) hosts the OPML import/export functionality previously in the `FeedListView` toolbar menu.

`APIKeySettingsView` provides a `TextField` for pasting an Anthropic API key, Save/Remove buttons, and a status indicator. Saved keys go directly to `KeychainService`. Also includes a "Model Configuration" section with fields for the Claude model identifier (validated: must start with `claude-`, lowercase alphanumeric + hyphens only) and max output tokens (validated: must be a positive integer). Both values are persisted in `UserDefaults` and validated inline with green checkmark / red indicator feedback. Validation logic is in `ModelValidation` and `MaxTokensValidation` enums in `ModelConfigurationValidator.swift` (under Services). Designed to be pushed from `SettingsView` or presented as a sheet (wrapped in `NavigationStack` by the caller when used as a sheet).

## Data Flow

```
RSSAppApp (@main)
    ├── ModelContainer (PersistentFeed, PersistentArticle, PersistentArticleContent)
    ├── UserDefaultsMigrationService → one-time migration from UserDefaults
    └── WindowGroup (.modelContainer)
        └── ContentView
            ├── @Environment(\.modelContext) → SwiftDataFeedPersistenceService
            └── FeedListView(persistence:)
                ├── @State FeedListViewModel(persistence:)
                │   ├── SwiftDataFeedPersistenceService (FeedPersisting protocol)
                │   │   └── ModelContext → SwiftData → [PersistentFeed], [PersistentArticle], ...
                │   └── FeedFetchingService (FeedFetching protocol) ← pull-to-refresh / post-import metadata refresh
                ├── NavigationStack
                │   ├── Empty → ContentUnavailableView + "Add Feed" button
                │   └── List → FeedRowView (title, description, unread count badge)
                │       └── NavigationLink(value: PersistentFeed.id)
                │           └── .navigationDestination → ArticleListView
                │               ├── FeedViewModel(feed:, persistence:)
                │               │   ├── FeedPersisting → cached [PersistentArticle] (shown immediately)
                │               │   ├── FeedFetchingService → network fetch → upsert to database
                │               │   ├── articles: [PersistentArticle]
                │               │   ├── markAsRead / toggleReadStatus
                │               │   ├── feedTitle: String
                │               │   ├── isLoading: Bool (only when no cached articles)
                │               │   └── errorMessage: String? (only when no cached articles)
                │               ├── Loading → ProgressView (only if no cached data)
                │               ├── Error → ContentUnavailableView + Retry (only if no cached data)
                │               └── Content → List
                │                   ├── Swipe actions: mark read/unread
                │                   └── ArticleRowView (thumbnail, title, snippet, date, read/unread styling)
                │                       └── tap → markAsRead → fullScreenCover → ArticleReaderView
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
                │                           └── sparkles button (AI icon)
                │                               ├── API key configured → sheet → ArticleSummaryView
                │                               │   ├── ArticleSummaryViewModel
                │                               │   │   └── ArticleExtractionService (hidden WKWebView)
                │                               │   │       └── Same native extraction pipeline
                │                               │   └── discuss button → sheet → ArticleDiscussionView
                │                               │       └── DiscussionViewModel
                │                               │           ├── KeychainService → Anthropic API key
                │                               │           └── ClaudeAPIService → URLSession SSE stream
                │                               └── No API key → sheet → APIKeySettingsView
                ├── gear button → push → SettingsView
                │   ├── API Key row → push → APIKeySettingsView
                │   └── Import / Export row → push → ImportExportView
                │       ├── Import Feeds → .fileImporter
                │       │   └── viewModel.importOPML(from:)
                │       │       ├── OPMLService.parseOPML → [OPMLFeedEntry]
                │       │       ├── Deduplicate via persistence.feedExists(url:)
                │       │       └── persistence.addFeed → SwiftData
                │       └── Export Feeds
                │           └── viewModel.exportOPML()
                │               ├── PersistentFeed → .toSubscribedFeed() conversion
                │               ├── OPMLService.generateOPML → Data
                │               └── ActivityShareView → UIActivityViewController
                └── Sheet: AddFeedView(persistence:)
                    └── @State AddFeedViewModel(persistence:)
                        ├── FeedFetchingService → validate URL + fetch title
                        └── persistence.addFeed → SwiftData
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

## Test Coverage

| Component | Test File | Coverage |
|-----------|-----------|----------|
| ContentView | RSSAppTests.swift | Verifies view instantiation |
| Article | ArticleTests.swift | Creation, nil optionals, Identifiable, Hashable, equality |
| SubscribedFeed | SubscribedFeedTests.swift | updatingMetadata preserves identity and clears error, does not mutate original, updatingError sets fields, updatingURL changes URL and clears error, Codable roundtrip with error fields, backward compatibility (missing error fields decode as nil) |
| DOMNode | DOMNodeTests.swift | Text/element accessors, tag name queries, tree traversal, visibility |
| HTMLUtilities | HTMLUtilitiesTests.swift | Tag stripping, entity decoding (amp, lt, gt, quot, apos, nbsp), whitespace collapse, HTML text escaping (amp, angle brackets, no-op), attribute escaping (amp, quot, lt, gt, no-op, multiple), image extraction (double/single quotes, multiple images, no images), og:image extraction (basic, reversed attributes, missing, case-insensitive, empty) |
| RSSParsingService | RSSParsingServiceTests.swift | Channel info, article count, basic fields, pubDate, snippets, raw description, thumbnail sources (media:thumbnail, media:content, enclosure, img fallback), thumbnail priority, ID derivation (guid, link), empty channel, malformed XML, empty data, missing fields, empty title, long snippet truncation, Atom XHTML content reconstruction (content, summary, content-overrides-summary, snippet generation, thumbnail extraction), Atom/RSS author extraction, Atom category term attributes, RSS category text, Atom enclosure links, RSS lastBuildDate, Atom feed-level updated date, default author/categories |
| KeychainService | KeychainServiceTests.swift | Save/load roundtrip, load when empty, delete clears value, overwrite updates value |
| ClaudeAPIService | ClaudeAPIServiceTests.swift | Request headers, request body JSON encoding (defaults + custom model/maxTokens), UserDefaults reading (default/stored/empty model, default/stored/zero/negative maxTokens, dynamic updates), SSE text delta parsing, non-delta event returns nil, malformed JSON returns nil, delta without text returns nil |
| ModelValidation + MaxTokensValidation | ModelConfigurationValidationTests.swift | Valid model ID with trimmed value, empty/whitespace, missing prefix, uppercase/spaces/special characters, claude-alone valid; valid positive integer with parsed value, minimum (1), large number, empty/whitespace, zero/negative/non-numeric/decimal invalid |
| CandidateScorer | CandidateScorerTests.swift | Content node identification in simple pages, scoring with class/id signals, link-density penalty, pruning of unlikely nodes |
| ContentAssembler | ContentAssemblerTests.swift | Plain text assembly, HTML tag preservation, attribute stripping, nested structure handling |
| ContentExtractor | ContentExtractorTests.swift | End-to-end extraction from DOM, site-specific extractor fallback, nil handling |
| MetadataExtractor | MetadataExtractorTests.swift | Title from OG meta, title from H1, byline from meta tags, byline from DOM elements |
| DOMSerializer (JS) | DOMSerializerTests.swift | WKWebView integration — text nodes, attributes, IDs, classes, ARIA roles, links, images, hidden elements, script/style filtering, meta tag capture, blog fixture serialization |
| Extraction Pipeline | ExtractionPipelineTests.swift | Full pipeline: HTML fixture → WKWebView serialize → Swift extract; JSON validity; meta tag capture |
| ArticleSummaryViewModel | ArticleReaderViewModelTests.swift | Pre-extracted content availability, extraction skip behavior, idle state |
| DiscussionViewModel | DiscussionViewModelTests.swift | hasAPIKey reflects keychain, send appends messages, chunks accumulate, input cleared, API error → error content, empty input ignored, no-key sets errorMessage |
| FeedViewModel | FeedViewModelTests.swift | Load success/failure, isLoading state, feedTitle default/update/unchanged on failure |
| FeedPersistenceService | FeedPersistenceServiceTests.swift | Feed CRUD (add, delete, update metadata/error/URL/cache headers, feedExists), article upsert (insert new, skip existing preserving read status), read/unread toggle, unread count, content cache (store, update, nil), cascade delete (feed → articles → content) |
| UserDefaultsMigrationService | UserDefaultsMigrationTests.swift | Migrate feeds, clear UserDefaults, migration flag, skip when migrated, empty defaults, preserve IDs |
| FeedStorageService | FeedStorageServiceTests.swift | Save/load roundtrip, add, remove, empty state, overwrite (legacy UserDefaults) |
| FeedURLValidator | FeedURLValidatorTests.swift | Valid HTTP/HTTPS, scheme prepend, empty/whitespace, non-HTTP schemes (ftp, feed), query parameters, whitespace trimming, scheme-only no host |
| OPMLService | OPMLServiceTests.swift | Parse flat/nested/empty OPML, folder flattening, missing attributes, title fallbacks, malformed XML, no body, round-trip generation, XML escaping, structure validation |
| FeedListViewModel | FeedListViewModelTests.swift | Load from storage, remove by object, remove by IndexSet, empty state, OPML import (add new, skip duplicates, skip intra-file duplicates, result counts, save to storage, rollback on failure, parse error), OPML export (sets data, error on failure), refresh (update metadata, partial failure, save to storage, empty no-op, isRefreshing state, error state on failure, error cleared on success, error persisted to storage), import+refresh integration |
| AddFeedViewModel | AddFeedViewModelTests.swift | Success, scheme prepend, invalid URL, duplicate detection, network error, error clearing |
| EditFeedViewModel | EditFeedViewModelTests.swift | Success with changed URL, unchanged URL dismisses, invalid URL, duplicate detection, network error, scheme prepend, URL pre-population |
