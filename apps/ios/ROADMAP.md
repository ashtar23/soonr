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
- view snapshot tests for the row and card, added once the components settled

**Snapshot testing, adopted in-repo.** A search-row layout regression reached
review past a green suite, because unit tests cannot see layout. The
`ViewSnapshot` helper renders with `ImageRenderer` and compares against
committed PNGs, with no third-party dependency: swift-snapshot-testing was
skipped because it would be the project's first test dependency and carries an
open crash on iOS 26 simulators (pointfreeco/swift-snapshot-testing#1089).

Four references cover the row at default, accessibility, and dark settings,
plus a card rail. Verified: byte-identical across runs, unchanged between iOS
26.2 and 26.5 so CI's dynamic simulator choice cannot flake, and a reverted
artwork frame fails three of the four by 18-21% of pixels. Comparison allows
1% of pixels to differ to absorb antialiasing; the gap between that and a real
regression is two orders of magnitude.

Limits: references hold on one iOS major version and in `en_US`, since release
dates use the current locale, and the suites skip themselves elsewhere. They
cover SwiftUI content only, not navigation or tab bar chrome, and `AsyncImage`
never loads during a render, so fixtures carry no artwork.

### Slice 4: Home discovery

- `GET /home/discovery` rails: coming soon, just released, worth watching
- horizontal `TitleCard` rails reusing the details destination search opens
- pull to refresh that keeps the current rails on screen
- empty rails dropped, all-empty and failure states with retry
- model and decoding tests

Deferred:

- `See all` screens and `nextCursor` pagination
- personalised rails and watchlist state on cards
- offline caching

### Slice 5: Authentication and session

- Debug, Staging, and Release xcconfig files; Release refuses to fall back to
  staging
- Supabase authentication through supabase-swift's Auth product, the project's
  first dependency
- sign in, sign out, and session restoration from the Keychain
- app-owned `SessionStore` injected through the environment
- `APIClient` attaches the session per request; a 401 surfaces as
  `APIError.unauthorized`

Deferred:

- sign up, which needs a username and availability checks (slice 6 sheet)
- signing out automatically on a rejected session, once authenticated
  endpoints exist to trigger it
- Sign in with Apple, and associated domains for password autofill

## Planned

### Slice 6: Watchlist

- authenticated watchlist loading
- add and remove from details
- optimistic state with rollback on failure
- one sign-in sheet with two entry points

**How authentication surfaces.** A sheet, opened only by a deliberate tap:
the Account row, or a gated action such as the watchlist button. No persistent
sign-up banner on browsing screens, and the watchlist button looks the same
signed in or out, so nothing nags a guest.

The sheet opens at a short detent, keeping the game visible behind it, and
grows to large when the email form needs the keyboard. Sign-up pushes inside
the same stack, and becomes a full-screen flow only if it grows past a couple
of steps.

The prompt carries the action that raised it, so signing in finishes what the
user started: tapping watchlist, signing in, and dismissing must leave the
title saved. Sign in with Apple joins the sheet once the capability and the
Supabase provider are configured.

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
