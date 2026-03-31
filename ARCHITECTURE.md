# Architecture

## Overview

RSS App is an iOS application for reading and managing RSS feeds. It is built as a pure SwiftUI app using the `@main` App lifecycle, targeting iOS 26 (iPhone only) with Swift 6 strict concurrency. There are no external package dependencies — the app uses only Apple system frameworks.

## Directory Structure

```
RSSApp/
├── App/                                # App lifecycle
│   └── RSSAppApp.swift                 # @main entry point — WindowGroup with ContentView
├── Views/                              # SwiftUI views
│   └── ContentView.swift               # Root view — centered "RSS App" label
└── Resources/
    └── Assets.xcassets/                # App icons and image assets
        ├── AccentColor.colorset/       # App accent color
        └── AppIcon.appiconset/         # App icon (1024x1024 placeholder)

RSSAppTests/
└── RSSAppTests.swift                   # Placeholder test suite (Swift Testing)
```

**Total: 2 source files, 1 test file.**

## Component Map

### App Layer

**Files:** `RSSAppApp.swift`

`RSSAppApp` is the entry point. It declares a single `WindowGroup` scene containing `ContentView`. The app uses the SwiftUI App lifecycle — no `AppDelegate` or `SceneDelegate`.

### Views

**Files:** `ContentView.swift`

`ContentView` displays a centered "RSS App" label. This is the scaffold starting point; views will be added here as the app grows.

## Data Flow

```
RSSAppApp (@main)
    └── WindowGroup
        └── ContentView (centered label)
```

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Pure SwiftUI App lifecycle | Simplest approach for a new iOS app; no UIKit boilerplate needed |
| Swift 6 strict concurrency | Catches data races at compile time; aligns with Apple's direction |
| No external dependencies | Reduces maintenance burden; RSS/XML parsing can be done with Foundation |
| iPhone only (TARGETED_DEVICE_FAMILY = 1) | Focused initial scope; iPad support can be added later |
| PBXFileSystemSynchronizedRootGroup | Modern Xcode project format — filesystem auto-syncs with project, no manual file reference management |
| Swift Testing over XCTest | Modern test framework with cleaner syntax (@Test, #expect); aligns with Kernova conventions |

## Test Coverage

| Component | Test File | Coverage |
|-----------|-----------|----------|
| ContentView | RSSAppTests.swift | Placeholder — verifies view instantiation |
