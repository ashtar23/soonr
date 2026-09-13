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

### Slice 6: Watchlist

- `POST` and `DELETE` on the API client, beside the existing `GET`
- watchlist membership read from the details payload rather than a second
  request
- one sign-in sheet with two entry points, and a redesigned account screen
- add and remove from details, optimistic with rollback and a gated sign-in
  that finishes the save the user started
- the watchlist tab, with empty, failure, and signed-out states
- `WatchlistStore` as the app's single source of truth, so the tab and details
  cannot disagree
- signing out when the server rejects the session

**One store, not realtime.** Screens first kept their own copy, and the two
disagreed exactly as expected: unsaving a title left its row on the tab, and
opening a saved title showed an empty bookmark for a frame. Both came from
this device's own action, so the answer was local state rather than a
subscription — no round trip beats state you already hold. Cross-device sync
stays a question for the notification slice, where the transport gets decided
anyway. The watchlist lives in Railway Postgres, not Supabase, so Supabase
Realtime would not cover it regardless.

Deferred:

- sign up, which still pushes a placeholder from the sheet
- `nextCursor` paging, with Home's `See all`
- Sign in with Apple, and associated domains for password autofill
- a retry for requests that time out against a sleeping staging container

### Slice 7: Sign up

- account creation from the sign-in sheet: email, username, password and a
  repeated password
- both availability checks debounced as the fields are typed, with the
  server's username pattern mirrored locally so malformed input costs no
  request
- signs in on success, because sign-up issues no session of its own
- `os.Logger` for requests, sessions and watchlist failures
- typed failures: `FailureReason` replaces prose in every state, and one
  `FailureView` replaces four hand-written ones

**Repeated password is required.** Nothing in this stack can reset a password,
so a typo would lock an account permanently. Until a reset flow exists,
confirming is the only protection a new account has.

**A "+" in a query was being sent as a space.** `URLComponents` leaves it
unescaped and the server read it as form data, so an email alias lost its
"+" and a search for "C++" lost both. Found by signing up with a real alias
against staging.

Deferred:

- password reset, which the repeated field currently stands in for
- `displayName`, which belongs with profile editing
- attributing a 409 to the email or the username, which needs the API to send
  the reason it already has

### Slice 8: Notifications

- the list, with signed-out, loading, empty, failure and refresh states
- opening one marks it read; swiping a row does too; the bell carries what is
  left, from the store that owns the list, so the two cannot disagree
- unread is a faint tint of the accent across the row, plus a semibold title,
  rather than a dot in a reserved column that indented every read row
- preferences: delivery, which events, and how far ahead, saved as they are
  changed
- `TitleDestination` so a notification can open a game it only knows the id
  and name of

**The server writes the copy, and it writes a label.** `message` is a category
("Release approaching") that reads the same on every row; the detail lives in
`subtitle` and the game in `titleName`. A row leading with `message` never says
which game it is about.

**That copy is frozen at generation time**, so a row generated on release day
still said "Releases today" a week later. `payload` already carries the target
release date, so the row works the sentence out against today and keeps the
server's copy as the fallback. No API change was needed: `payload` was in the
response all along.

Deferred:

- marking something unread: the API has five notification endpoints and none
  of them can clear `read_at`
- push, which no part of the stack can deliver, so the screen does not offer
  the switch
- `release_date_changed` notifications, which nothing generates yet
- `nextCursor` paging

### Slice 10: Push delivery

Its own slice rather than a leftover of Slice 8, and as much `apps/api` as iOS:
APNs credentials, device-token storage, a send path, and the client half.

- token-based APNs (ES256 over HTTP/2), sandbox and production chosen per
  device rather than per build
- device tokens stored with the token as the primary key, so a rotated token
  replaces itself; 410 Unregistered and 400 BadDeviceToken delete the device
- permission asked on the way _on_ — turning the switch on is what prompts, so
  the system alert follows a request for notifications rather than arriving
  unexplained at launch
- a refused switch opens Soonr's own notification settings, because iOS shows
  its prompt once per install and Settings is the only way back
- the icon badge follows the unread count the list already owns

**The build flag and the signature disagree.** A Staging build run from Xcode is
development-signed, so it holds a sandbox token while `DEBUG` is undefined.
Claiming production for it has APNs answer `BadDeviceToken`, which the delivery
pass reads as a dead device and deletes. The environment is read from the signed
provisioning profile instead.

Five of the bugs this slice produced were only findable on a device or in
production: a delegate isolated with `nonisolated` crashed on tap, a deep link
never fired because `.onChange` does not run when a tab's content is first
created, the badge stuck, and a notification opened from a push did not clear.

### Slice 11: Notifications in realtime

The list and the preferences screen follow the server without a refresh.

- `NotificationStreaming` behind a `URLSessionWebSocketTask` transport, with
  reconnect and backoff, and a heartbeat so a socket dropped behind NAT is
  found on the next ping rather than at the next read
- held only while signed in and the scene is active, from one predicate rather
  than a call at each of sign-in, sign-out, and scene change
- one connection fanned out to both stores, because a stream has one consumer

**The server pushes invalidations, not records.** A change arrives as
`{"type":"notifications.changed","scope":"records"}` with no payload, so the
answer is a refetch. That is simpler than it sounds: no client-side merge, no
dedupe against the push that may describe the same thing, and a missed event
costs latency rather than correctness.

**Which makes the echo the expensive part.** The trigger fires per row on insert
or update, and an update to `read_at` counts, so this device's own read comes
straight back as news it already acted on. The store counts the events its
writes are owed — exactly, because marking everything read reports how many rows
moved — and collapses bursts into one refetch. Without it, twenty unread
notifications cost forty requests to mark read.

Deferred:

- a repeatedly rejected token reconnects rather than ending the session, unlike
  the HTTP path; a background socket is a bad place to sign someone out from
- `nextCursor` paging, now Slice 12

## Planned

### Slice 12: Paging

Both the notifications list and the watchlist fetch the first page and drop
`nextCursor`. Realtime makes it sooner rather than later: the list now grows
while it is on screen. One pattern, established once, used by both.

### Slice 9: Production hardening

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
