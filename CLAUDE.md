# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> Design philosophy and UI guidelines are in [SPEC.md](SPEC.md).

## Build & Test

This is an Xcode project (not Swift Package Manager). Build and test via `xcodebuild`:

```bash
# Build
xcodebuild -project RSSApp.xcodeproj -scheme RSSApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath DerivedData build

# Run tests
xcodebuild -project RSSApp.xcodeproj -scheme RSSApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath DerivedData test

# Run a single test suite
xcodebuild -project RSSApp.xcodeproj -scheme RSSApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath DerivedData test -only-testing:RSSAppTests/RSSAppTests
```

The `-derivedDataPath DerivedData` flag ensures build output goes to a deterministic local `DerivedData/` directory (already gitignored) instead of the per-path-hashed `~/Library/Developer/Xcode/DerivedData/` location. This avoids glob ambiguity when worktrees or parallel builds create multiple DerivedData folders.

Requires **iOS 26**, **Xcode 26**, and **Swift 6**. iPhone only (no iPad target).

## Architecture

> Full directory structure, component map, data flow diagrams, design decisions, and test coverage details are in [ARCHITECTURE.md](ARCHITECTURE.md). Consult it before making structural changes. The summary below is a quick reference; if it conflicts with ARCHITECTURE.md, ARCHITECTURE.md is authoritative.

RSS App is a pure SwiftUI iOS app using the `@main` App lifecycle. It targets iPhone and uses Swift 6 strict concurrency.

**Data flow:** `RSSAppApp` → `ContentView` → `FeedListView` (`NavigationStack` root, `FeedListViewModel` + `FeedStorageService` + `OPMLService` + `FeedFetchingService`) → tap feed → `ArticleListView` (`FeedViewModel` per feed) → tap article → `ArticleReaderView`. `FeedFetchingService` fetches RSS XML via `URLSession`, `RSSParsingService` parses it with `XMLParser` into `Article` models. Subscribed feeds are persisted in `UserDefaults` via `FeedStorageService`. OPML import/export via `OPMLService` allows bulk feed exchange through the standard OPML format. Pull-to-refresh on the feed list re-fetches RSS metadata for all feeds; OPML import automatically refreshes metadata after adding feeds.

**Concurrency model:** The codebase uses Swift 6 strict concurrency. Use `@MainActor` for any UI-related state. Services that perform I/O should be `Sendable` structs or actors.

**No external dependencies.** The app uses only Apple system frameworks.

## Development Guidelines

### Unit Tests

When adding new functionality or modifying existing behavior, include unit tests for the changes. Follow the existing patterns in `RSSAppTests/`:

- Use Swift Testing (`@Suite`, `@Test`, `#expect`) — not XCTest
- Create mock implementations using protocols (see `RSSAppTests/Mocks/` when created)
- Test models, services, and view models — UI views don't need unit tests
- Test both happy paths and error paths; use error injection in mocks (e.g., setting a `throwError` property)
- Reuse shared test helpers and factories rather than duplicating setup logic across test files
- Run the full test suite before committing to ensure nothing is broken

### Logging

The app uses Apple's `os.Logger` (subsystem `com.nicholas-lonsinger.rss-app`) with per-component categories. Each service, view model, or model that logs declares a `private static let logger`. When adding or modifying functionality, include log calls at appropriate levels:

| Level | When to use | Persistence |
|-------|-------------|-------------|
| `.debug` | Method entry with parameter snapshots, intermediate states, per-item iteration results. Diagnostic detail only useful when actively investigating. | Discarded unless streaming via Console.app or `log stream` |
| `.info` | General operational context: routine progress, non-critical outcomes, sub-step completion. | In-memory only; evicted under pressure |
| `.notice` | Definitive lifecycle events: feed added/removed, refresh completed, app launch. Events you need for post-mortem analysis. | Persisted to disk |
| `.warning` | Unexpected but recoverable situations: missing data, fallback paths taken, degraded operation. | Persisted to disk |
| `.error` | Failures: operations that did not complete, exceptions caught, error states entered. | Persisted to disk |
| `.fault` | Programming errors: impossible states, compile-time-known inputs that failed lookup. Paired with `assertionFailure`. | Persisted to disk; always visible; never redacted |

**Guidelines:**
- Every new service or view model should declare its own `private static let logger = Logger(subsystem: "com.nicholas-lonsinger.rss-app", category: "ComponentName")`
- State transitions and irreversible actions should be `.notice`
- Method entry points in complex flows should have `.debug` logs with relevant parameter values
- Do not use `print()`, `NSLog()`, or file-based logging

### Defensive Unwrapping

When calling an API that returns an optional but is invoked with compile-time-known inputs (SF Symbol names, known resource identifiers, hardcoded keys), use `assertionFailure` with a graceful fallback:

```swift
guard let value = knownGoodAPI("compile-time-constant") else {
    logger.fault("Descriptive message '\(context, privacy: .public)'")
    assertionFailure("Descriptive message: \(context)")
    return fallbackValue
}
```

- **Debug builds** crash immediately at the call site, catching typos and deployment-target mismatches on first test run
- **Release builds** return the fallback and log at `.fault` level for post-mortem diagnosis
- Do not force-unwrap (`!`) — it crashes end users. Do not silently return a fallback without `assertionFailure` — it masks bugs during development.

### File Operations

- When deleting files, prefer `trash` over `rm` whenever possible (moves to Trash instead of permanent deletion).

### Review Feedback Handling

When reviewing code — via review tools (`/simplify`, `/review-pr`, etc.), post-implementation review agents, external PR review feedback (bot or human), or while working on adjacent code — every finding must be triaged into one of four categories:

| Category | Action | When to use |
|----------|--------|-------------|
| **Fix now** | Apply the fix as part of the current work | Valid finding, in scope, reasonable effort |
| **Fix later** | File a GitHub issue (see [Review Debt Tracking](#review-debt-tracking) below) | Valid finding, but out of scope or too large for the current task |
| **Annotate** | Add a `RATIONALE:` comment (see [Intentional Pattern Annotations](#intentional-pattern-annotations) below) | Code looks wrong or unconventional but is correct for a project-specific reason |
| **Dismiss** | No action needed | Pure style nits, cosmetic preferences, trivial improvements with negligible impact |

#### Review Debt Tracking

Valid findings that are **out of scope** for the current task must be captured as GitHub issues rather than silently dropped.

**What to capture** (important + moderate severity):
- Bugs, correctness problems, or logic errors
- Security concerns
- Performance issues
- Meaningful refactoring opportunities or non-trivial code smells
- Missing test coverage for critical paths

**Issue format:**

~~~bash
gh issue create \
  --title "<concise description of the finding>" \
  --label "<review-debt/label>" \
  --body "$(cat <<'EOF'
## Found during
<PR #N / review of `FileName.swift` / context description>

## Description
<What the issue is and why it matters>

## Location
<File path(s) and line number(s) or function name(s)>

## Suggested fix
<Brief suggestion if one is obvious, otherwise omit this section>
EOF
)"
~~~

**Labels** — use the most specific match:

| Label | When to use |
|-------|-------------|
| `review-debt/bug` | Correctness issues, logic errors, potential crashes |
| `review-debt/security` | Security concerns, unsafe patterns |
| `review-debt/performance` | Inefficient code paths, unnecessary allocations |
| `review-debt/refactor` | Code smells, duplication, poor abstractions |
| `review-debt/test-gap` | Missing or insufficient tests for critical code |

**Guidelines:**
- **File issues immediately** — do not list qualifying findings as "skipped" and wait for the user to ask. If a finding meets the severity criteria above, create the issue as part of the review flow before summarizing results.
- Always check for existing issues before creating duplicates
- Reference the source PR or file context in the issue body
- Keep issue titles actionable and specific (e.g., "Add error handling for network timeout in FeedService" not "Improve error handling")
- When multiple related findings exist, group them into a single issue if they share a root cause
- After creating issues, mention them in the conversation so the user is aware

#### Intentional Pattern Annotations

When a review flags code that *looks* wrong or unconventional but is **intentionally correct** for a project-specific reason, add an inline comment with the `RATIONALE:` prefix explaining why. This prevents the same pattern from being re-flagged in future reviews.

**When to annotate:**
- The code contradicts a general best practice but is correct here due to framework constraints, performance requirements, or architectural decisions
- A reviewer (human or automated) would reasonably flag this without project-specific context
- The reason is not already documented in CLAUDE.md, ARCHITECTURE.md, or an adjacent comment

**Format:**

```swift
// RATIONALE: Description of why this unconventional pattern is correct here.
```

**Guidelines:**
- Keep annotations concise — explain *why* the pattern is correct, not *what* the code does
- If the same rationale applies project-wide (not just at one call site), consider adding it to CLAUDE.md or ARCHITECTURE.md instead of repeating the comment on every instance
- `RATIONALE:` comments are greppable — use `grep -r "RATIONALE:"` to audit all intentional deviations
- Do not use `RATIONALE:` for general explanatory comments — reserve it strictly for patterns that would otherwise be flagged as issues

## Git Workflow

### Branch Naming

Before starting work in a worktree, create a descriptively-named branch. Use the format `<type>/<short-description>`, where `<type>` matches the commit type prefixes (e.g., `feat`, `fix`, `refactor`):

```
feat/feed-list-view
fix/parsing-date-format
refactor/extract-feed-service
```

Create and switch to the branch before making any changes:

```bash
git checkout -b feat/feed-list-view
```

Keep descriptions concise (2-4 words, kebab-case). The branch name should make the PR's purpose clear at a glance.

### Commit Messages

These conventions apply to **all** forms of committing: local commits, PR squash/merge commits, and any other git operations that produce commits.

Use the following format for all commits:

```
<type>: <concise subject line>

## Summary
- <user-facing intent: what capability was added/fixed/changed and why>

## Changes
- <implementation details: specific files, types, or components modified>

## Test plan
- [ ] <verification step as a checkbox>
```

A `## Notes` section may be added optionally if there are caveats, follow-ups, or things reviewers should know.

### Type prefixes

| Prefix     | Usage                                      |
|------------|--------------------------------------------|
| `feat`     | New feature or capability                  |
| `fix`      | Bug fix                                    |
| `refactor` | Code restructuring with no behavior change |
| `docs`     | Documentation only                         |
| `test`     | Adding or updating tests                   |
| `chore`    | Build, CI, tooling, or dependency updates  |
| `style`    | Formatting, whitespace, or cosmetic changes|

### Example

```
feat: Add RSS feed list view

## Summary
- Display a list of subscribed RSS feeds with title and last-updated date
- Enables users to see all their feeds at a glance

## Changes
- Add FeedListView with NavigationStack
- Add FeedRowView for individual feed display
- Add FeedListViewModel with @Observable

## Test plan
- [ ] Built successfully for iOS 26
- [ ] Tested feed list display with sample data
- [ ] All existing tests pass
```

### Scoping the message

Commit messages must reflect the full intent and scope of all changes, not just the last operation performed. Before writing a commit message, review both the conversation context (what the user asked for, the steps taken) and the staged diff holistically. Lead with the primary purpose; secondary details (naming conventions, formatting choices) belong in the body.

The `Co-Authored-By` trailer is automatically appended by Claude Code and should not be duplicated in the commit message body.

### Merging Pull Requests

When merging PRs with `gh pr merge`, always squash-merge with `--squash --subject` using the PR title and appending the PR number in parentheses (e.g., `--squash --subject "fix: Title (#11)"`), matching the repo's existing convention.

**Do not use `--delete-branch`.** The repo has `delete_branch_on_merge` enabled on GitHub, so remote branches are auto-deleted. The `--delete-branch` flag causes `gh` to run `git checkout main` locally, which fails in worktree contexts.

**Linking issues for auto-close:** When a PR resolves GitHub issues, include `Closes #N` (or `Fixes #N`) in the PR body — not just a table reference like `| #N |`. GitHub only auto-closes issues when the merge commit or PR body contains the exact keywords `closes`, `fixes`, or `resolves` followed by `#N`. Place them in the summary section or as a standalone line (e.g., `Closes #12, #34, #56`).

#### Post-merge cleanup

After a successful merge, run the following steps to clean up the local branch and sync:

1. `gh pr view <N> --json state -q .state` — confirm `"MERGED"` before deleting anything
2. If in a worktree: switch to the worktree's local branch, which is always the worktree name with a `worktree-` prefix (e.g., `git checkout worktree-expressive-yawning-sutton` for a worktree named `expressive-yawning-sutton`)
3. `git branch -D <merged-branch>`
4. `git branch -d -r origin/<merged-branch>`
5. `git pull`

### Post-Commit

After a commit/push, if any new preferences or insights emerged during the work, ask the user if they'd like to add them to memory.

## Architecture Change Protocol

After completing any task that hits one or more of the following triggers, suggest follow-up updates before considering the task complete.

### Triggers
- Added, removed, renamed, or moved a file or directory
- Changed how components communicate (new API surface, changed data flow, new service)
- Added or removed a dependency or framework
- Changed build configuration, entitlements, or tooling
- Created a new public type/protocol or significantly changed an existing one
- Changed the concurrency model or actor isolation of a component

### Required Follow-ups

1. **[ARCHITECTURE.md](ARCHITECTURE.md)** — Read the relevant sections first, then propose specific, targeted updates to reflect the change. Update the directory structure, component map, design decisions, or test coverage sections as needed. Do not rewrite the entire file — make surgical edits.

2. **Testing** — For any new public function, type, or component:
   - Write tests following the patterns in RSSAppTests/ (Swift Testing, mocks, factories)
   - If tests are deferred, explicitly state what's needed and why it was skipped

3. **CLAUDE.md** — Update only if build commands, the concurrency model summary, or the data flow summary changed. Preserve commit message format and development guidelines as-is.

4. **Maintenance Notes** — At the end of your response, include a summary:

   ### Maintenance Notes
   - ✅ Updated ARCHITECTURE.md directory structure
   - ✅ Added tests for NewComponent
   - ⚠️ No tests yet for `newFunction()` — needs mock for ExternalDependency
   - ✅ CLAUDE.md unchanged (no structural impact)
