# Architecture

## Overview

RSS App is an iOS application for reading and managing RSS feeds. It is built as a pure SwiftUI app using the `@main` App lifecycle, targeting iOS 26 (iPhone only) with Swift 6 strict concurrency. There are no external package dependencies — the app uses only Apple system frameworks.

## Directory Structure

```
RSSApp/
├── App/                                # App lifecycle
│   └── RSSAppApp.swift                 # @main entry point — WindowGroup with ContentView
├── Models/                             # Data models
│   ├── Article.swift                   # Article (Identifiable, Hashable, Sendable)
│   └── RSSFeed.swift                   # Feed container with channel info and articles
├── Services/                           # Business logic and networking
│   ├── FeedFetchingService.swift       # FeedFetching protocol + URLSession implementation
│   ├── HTMLUtilities.swift             # HTML tag stripping, entity decoding, image extraction
│   └── RSSParsingService.swift         # XMLParser-based RSS 2.0 parser
├── ViewModels/                         # View state management
│   └── FeedViewModel.swift             # @Observable @MainActor — feed loading state
├── Views/                              # SwiftUI views
│   ├── ContentView.swift               # Root view — NavigationStack with FeedViewModel
│   ├── ArticleListView.swift           # Feed article list with loading/error/content states
│   ├── ArticleRowView.swift            # Single article row — thumbnail, title, snippet, date
│   └── ArticleDetailView.swift         # Article detail — title, date, plain text body
└── Resources/
    └── Assets.xcassets/                # App icons and image assets
        ├── AccentColor.colorset/       # App accent color
        └── AppIcon.appiconset/         # App icon (1024x1024 placeholder)

RSSAppTests/
├── RSSAppTests.swift                   # Root test suite (ContentView instantiation)
├── Helpers/
│   └── TestFixtures.swift              # Sample RSS XML, factory methods for Article/RSSFeed
├── Mocks/
│   └── MockFeedFetchingService.swift   # FeedFetching mock with injectable results/errors
├── Models/
│   └── ArticleTests.swift              # Article creation, identity, hashable
├── Services/
│   ├── HTMLUtilitiesTests.swift        # Tag stripping, entity decoding, image extraction
│   └── RSSParsingServiceTests.swift    # Channel parsing, thumbnails, IDs, edge cases
└── ViewModels/
    └── FeedViewModelTests.swift        # Load success/failure, state transitions
```

**Total: 10 source files, 7 test files.**

## Component Map

### App Layer

**Files:** `RSSAppApp.swift`

`RSSAppApp` is the entry point. It declares a single `WindowGroup` scene containing `ContentView`. The app uses the SwiftUI App lifecycle — no `AppDelegate` or `SceneDelegate`.

### Models

**Files:** `Article.swift`, `RSSFeed.swift`

`Article` is the core data model representing a single feed item. It stores the title, link, raw HTML description, a plain-text snippet, publication date, and thumbnail URL. It conforms to `Identifiable` (for lists), `Hashable` (for navigation), and `Sendable` (for concurrency safety).

`RSSFeed` represents a parsed feed channel — title, link, description, and an array of `Article` values. Also `Sendable`.

### Services

**Files:** `FeedFetchingService.swift`, `RSSParsingService.swift`, `HTMLUtilities.swift`

`FeedFetching` is a protocol defining `fetchFeed(from:) async throws -> RSSFeed`. `FeedFetchingService` is the concrete implementation that fetches data via `URLSession.shared` and delegates parsing to `RSSParsingService`.

`RSSParsingService` wraps Foundation's `XMLParser` to parse RSS 2.0 XML into `RSSFeed` and `Article` values. It handles `<media:thumbnail>`, `<media:content>`, `<enclosure>`, and `<img>` fallback for thumbnail discovery. Internally uses a synchronous `XMLParserDelegate` class marked `@unchecked Sendable` (safe because it is created and consumed within a single synchronous `parse()` call).

`HTMLUtilities` provides static methods for stripping HTML tags/entities to plain text and extracting the first `<img>` URL from HTML content.

### ViewModels

**Files:** `FeedViewModel.swift`

`FeedViewModel` is `@Observable` and `@MainActor`. It holds the article list, loading state, and error state. It accepts a `FeedFetching` dependency (defaulting to `FeedFetchingService`) for testability. Currently loads from a hardcoded Ars Technica feed URL.

### Views

**Files:** `ContentView.swift`, `ArticleListView.swift`, `ArticleRowView.swift`, `ArticleDetailView.swift`

`ContentView` is the root view. It creates a `FeedViewModel` as `@State` and wraps `ArticleListView` in a `NavigationStack`.

`ArticleListView` shows three states: loading spinner, error with retry button, or a plain-style list of articles. Supports pull-to-refresh. Uses `.navigationDestination(for: Article.self)` for navigation.

`ArticleRowView` displays a single article row with a 60×60 `AsyncImage` thumbnail, headline title, subheadline snippet, and caption-style relative date.

`ArticleDetailView` shows the full article with title (`.title2` + `.semibold`), publication date, and plain-text body stripped from HTML. Includes a Safari toolbar link to open the original article.

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
                ├── ArticleListView
                │   ├── Loading → ProgressView
                │   ├── Error → ContentUnavailableView + Retry
                │   └── Content → List
                │       └── ArticleRowView (thumbnail, title, snippet, date)
                └── ArticleDetailView (title, date, body, Safari link)
```

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Pure SwiftUI App lifecycle | Simplest approach for a new iOS app; no UIKit boilerplate needed |
| Swift 6 strict concurrency | Catches data races at compile time; aligns with Apple's direction |
| No external dependencies | Reduces maintenance burden; RSS/XML parsing can be done with Foundation |
| iPhone only (TARGETED_DEVICE_FAMILY = 1) | Focused initial scope; iPad support can be added later |
| PBXFileSystemSynchronizedRootGroup | Modern Xcode project format — filesystem auto-syncs with project, no manual file reference management |
| Swift Testing over XCTest | Modern test framework with cleaner syntax (@Test, #expect) |
| `@Observable` over `ObservableObject` | Modern observation API; less boilerplate (no `@Published`); better performance |
| `FeedFetching` protocol for DI | Enables mock injection for ViewModel tests without network access |
| `XMLParser` with `@unchecked Sendable` delegate | Synchronous parsing within a single method call; delegate never escapes scope |
| Plain text article body | Simplest first approach; HTML stripping via regex avoids WebKit dependency; upgradeable to rich text later |
| Thumbnail priority: media:thumbnail → media:content → enclosure → img in HTML | Covers common RSS image patterns; ordered by specificity |

## Test Coverage

| Component | Test File | Coverage |
|-----------|-----------|----------|
| ContentView | RSSAppTests.swift | Verifies view instantiation |
| Article | ArticleTests.swift | Creation, nil optionals, Identifiable, Hashable, equality |
| HTMLUtilities | HTMLUtilitiesTests.swift | Tag stripping, entity decoding (amp, lt, gt, quot, apos, nbsp), whitespace collapse, image extraction (double/single quotes, multiple images, no images) |
| RSSParsingService | RSSParsingServiceTests.swift | Channel info, article count, basic fields, pubDate, snippets, raw description, thumbnail sources (media:thumbnail, media:content, enclosure, img fallback), thumbnail priority, ID derivation (guid, link), empty channel, malformed XML, empty data, missing fields, empty title, long snippet truncation |
| FeedViewModel | FeedViewModelTests.swift | Load success, load failure, error clearing on retry, article replacement on refresh, isLoading state |
