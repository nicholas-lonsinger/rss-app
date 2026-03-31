# SPEC.md

Design philosophy and guidelines for RSS App.

## Code Approach

- Do not settle for workarounds or hacks. Fix root causes with proper refactors, even when the change is larger than a quick patch.
- Aggressively identify code that looks like a shortcut or band-aid. Either fix it in scope or file a GitHub issue for a future pass.
- GitHub issues serve as durable context — when a fix is deferred, the issue should capture enough detail to address it later without rediscovery.
- Prefer the simpler path first. Always attempt or plan the straightforward solution before introducing complexity through flags, intercepts, overrides, special cases, shims, or conditional branching.

## GUI Design

### General

- Match Apple's built-in app conventions and visuals (News, Safari, etc.) whenever possible/feasible.
- If matching Apple's conventions would require significant effort or complexity, ask the user first before proceeding.
- Use SF Symbols exclusively for icons — no custom image assets (except the app icon).

### Layout

- Pure SwiftUI layout — no UIKit hosting unless strictly necessary for a missing SwiftUI capability.
- Use `NavigationStack` for drill-down navigation.
- Use `TabView` if/when multiple top-level sections are needed.
- Respect safe areas and Dynamic Type.

### Typography

- `.largeTitle` + `.fontWeight(.bold)` — screen titles (via `.navigationTitle`)
- `.title2` + `.fontWeight(.semibold)` — section headings
- `.headline` — important labels and row titles
- `.body` — primary content
- `.subheadline` / `.caption` — secondary text, metadata, timestamps
- `.system(.caption, design: .monospaced)` — code snippets, URLs, and paths

### Spacing

- `VStack(spacing: 24)` — between major sections
- `VStack(spacing: 12)` — between grouped elements
- `VStack(spacing: 8)` — compact grouping (icon + label)
- `VStack(spacing: 2–4)` — tightly related items
- `HStack(spacing: 8)` — standard inline spacing

### Colors

- Use semantic system colors (`.primary`, `.secondary`, `.accentColor`) — no hardcoded RGB values.
- Destructive actions: `.red` foreground.
- Status indicators: use `.green` for success, `.orange` for warning/in-progress, `.red` for error.

### Controls

- `.formStyle(.grouped)` for settings forms.
- `.listStyle(.plain)` or `.listStyle(.insetGrouped)` for content lists.
- Default button style in lists; `.bordered` or `.borderedProminent` for dialog actions.
- `role: .destructive` for delete confirmations.
- Use swipe actions for list item operations (delete, archive, mark read).
- `ProgressView` for loading states.

### Accessibility

- All interactive elements must have meaningful accessibility labels.
- Support Dynamic Type — never use fixed font sizes.
- Ensure sufficient color contrast for all text.
- Support VoiceOver navigation ordering.
