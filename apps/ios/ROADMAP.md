# Soonr iOS Vertical-Slice Roadmap

## Working agreement

Each slice delivers one visible user outcome through UI, state, services, and
verification. Supporting work is included only when that outcome requires it.
Architecture improvements are extracted at the point of real reuse.

## Definition of done

A slice is complete when:

- the user-visible happy path works on the latest iOS simulator
- compatibility-sensitive behavior works on the oldest supported iOS 17 runtime
- loading, empty, error, and retry behavior are handled where applicable
- feature logic has deterministic Swift Testing coverage
- previews use mock data and perform no live network requests
- the app target builds without new actionable warnings
- configuration and accessibility implications have been reviewed
- the change is small enough for one focused commit

## Completed

### Slice 0: Native walking skeleton

- Swift 6 and SwiftUI application with an iOS 17 deployment target
- Home, Watchlist, Notifications, Search, and Account tabs
- iOS 17 tab fallback, modern iOS 18 tabs, and native iOS 26 Liquid Glass behavior
- placeholder routes for authentication and settings
- primary navigation contract tests

### Slice 1: Guest title search

- debounced search with a two-character minimum
- Soonr `/titles` API integration through `URLSession`
- idle, loading, results, empty, failure, and retry states
- accessible result rows with remote cover images
- injected search capability with deterministic model tests
- staging API default with an Xcode environment override

### Slice 2: Search result to title details

- value-based navigation from search results to title details
- `GET /titles/:titleId` integration with loading, not-found, failure, and retry
  states
- cover, name, description, genres, developers, publishers, platforms, and
  per-platform release dates; sections hide when staging data is sparse
- compact landscape result rows with release countdown badges and resized RAWG
  artwork
- `AppDependencies` composition root; `SearchView` no longer builds the live API
- shared `APIClient` request core, including cancellation normalization
- Xcode synchronized folders, so new files need no project file edits
- Swift OpenAPI Generator evaluated and deferred (see Architecture)
- request, decoding, formatting, and model tests

Deferred:

- watchlist mutation and `isInWatchlist` display
- authenticated personalization
- website link, sharing, and rich media
- offline details caching

### Slice 3: Theme and design-system foundation

- appearance preference (system, light, dark) and a choice of accent colour,
  persisted and applied at the app root
- brand accent asset with light and dark values; everything else stays on
  Apple's semantic colours
- `DesignSystem` folder owning `TitleArtwork`, `TitleRow`, `ReleaseBadge`, and
  `PlaceholderScreen`
- result rows scale with Dynamic Type and stack at accessibility sizes
- decide on view snapshot tests once these components stabilize

**Snapshot testing, deferred here deliberately.** A search-row layout
regression reached review past a green suite, because unit tests cannot see
layout. A spike showed `ImageRenderer` can snapshot views inside the existing
test target with no dependency: about 0.25s per view, byte-stable across runs
on one runtime, and it distinguishes the broken layout from the fixed one.
References differ per iOS version, so they must be pinned to one runtime, and
they only cover SwiftUI content, not navigation or tab bar chrome.

Two options remain open: an in-repo helper of roughly 100 lines, or
swift-snapshot-testing, which is currently blocked by an open crash on iOS 26
simulators (pointfreeco/swift-snapshot-testing#1089) and would be the
project's first third-party dependency. Snapshots are worth adopting only
after the components they capture stop changing, otherwise every design change
means re-recording.

## Planned

### Slice 4: Home discovery

- upcoming, latest, and popular sections from `apps/api`
- reuse title presentation and details navigation
- refresh, empty, and partial-failure behavior

### Slice 5: Authentication and session

- Supabase Swift authentication
- sign in, sign up, sign out, and session restoration
- app-owned observable session state
- authenticated bearer-token middleware for `apps/api`
- explicit Debug, Staging, and Release configuration

### Slice 6: Watchlist

- authenticated watchlist loading
- add and remove from details
- optimistic state with rollback on failure
- signed-out guidance

### Slice 7: Notifications

- notification list and unread state
- mark-as-read behavior
- preferences
- realtime or push delivery only after the HTTP flow is stable

### Slice 8: Production hardening

- OpenAPI contract generation or drift checks
- structured logging and crash reporting
- offline and cache policy
- localization and complete accessibility audit
- critical XCTest UI flows
- CI, signing, TestFlight, privacy declarations, and release readiness

## Decision log triggers

Create a short architecture decision record only for choices with lasting cost,
such as adopting OpenAPI generation, introducing Swift packages, selecting an
image cache, or changing persistence strategy. Routine feature work does not need
a separate design document.
