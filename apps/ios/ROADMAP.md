# Soonr iOS Vertical-Slice Roadmap

## Working agreement

Each slice delivers one visible user outcome through UI, state, services, and
verification. Supporting work is included only when that outcome requires it.
Architecture improvements are extracted at the point of real reuse.

## Definition of done

A slice is complete when:

- the user-visible happy path works on an iOS 26 simulator
- loading, empty, error, and retry behavior are handled where applicable
- feature logic has deterministic Swift Testing coverage
- previews use mock data and perform no live network requests
- the app target builds without new actionable warnings
- configuration and accessibility implications have been reviewed
- the change is small enough for one focused commit

## Completed

### Slice 0: Native walking skeleton

- Swift 6 and SwiftUI iOS 26 application target
- Home, Watchlist, Notifications, Search, and Account tabs
- native Liquid Glass tab behavior
- placeholder routes for details, authentication, and settings
- primary navigation contract tests

### Slice 1: Guest title search

- debounced search with a two-character minimum
- Soonr `/titles` API integration through `URLSession`
- idle, loading, results, empty, failure, and retry states
- accessible result rows with remote cover images
- injected search capability with deterministic model tests
- staging API default with an Xcode environment override

## Next

### Slice 2: Search result to title details

**User outcome:** A guest can select a search result and view useful details for
that game.

Minimum scope:

- make search rows value-based navigation links
- connect `GET /titles/:titleId`
- show cover, name, description, genres, developers, publishers, platforms, and
  release information
- support loading, not-found, network-failure, and retry states
- introduce app-root dependency composition instead of constructing the live API
  dependency inside `SearchView`
- extract common request behavior now that a second endpoint needs it
- add model and response-decoding tests

Deferred:

- watchlist mutation
- authenticated personalization
- sharing and rich media
- offline details caching

## Planned

### Slice 3: Theme and design-system foundation

- system, light, and dark preferences
- semantic colors and adaptive brand assets
- initial reusable title artwork and metadata components
- light, dark, increased-contrast, and Dynamic Type checks

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
