# Soonr iOS Architecture

## Purpose

Soonr for iOS is a native SwiftUI client supporting iOS 17 and newer. It adopts
new platform capabilities through availability-gated enhancements while keeping
system-native fallbacks for older supported releases. The app is built as small
end-to-end vertical slices while preserving clear ownership boundaries. This
document records the rules that should remain stable as features are added.

The current codebase is a single application target. Folders communicate intent;
they are not separate modules yet. Swift packages should only be introduced when
team ownership, reuse, or build performance gives us a concrete reason.

`Soonr` and `SoonrTests` are Xcode synchronized folders, so the folder structure
on disk is the project structure. Adding, moving, or removing a source file
needs no `project.pbxproj` edit, which keeps that file out of merge conflicts.
Files land in the target that owns their folder.

## Guiding principles

- Build the smallest user-visible flow through UI, state, API, and tests.
- Keep state close to its owner; app-global state must be genuinely global.
- Depend on small capabilities rather than concrete infrastructure.
- Keep network, authentication, persistence, and logging out of SwiftUI views.
- Extract shared code after a second real consumer appears, not in anticipation.
- Prefer Apple frameworks and Swift concurrency before adding dependencies.
- Keep iOS 18+ and iOS 26+ APIs behind explicit availability checks with an
  iOS 17 fallback.
- Every completed slice must build, have deterministic tests, and receive a
  simulator smoke test on the latest runtime. Compatibility-sensitive changes
  must also be exercised on the oldest supported runtime when it is available.

## Dependency and data flow

```text
SoonrApp / app composition
       |
       +-- creates live dependencies
       |
       v
SwiftUI feature view
       |
       v
@Observable feature model
       |
       v
small capability protocol
       |
       v
infrastructure implementation
       |
       v
apps/api -> Postgres / external providers
```

Dependencies point from presentation toward capabilities. Infrastructure
implements those capabilities, and the app composition root selects the live
implementation. Tests and previews supply deterministic substitutes.

## Folder ownership

### `App`

Owns application startup, dependency composition, top-level navigation, tabs,
and app lifecycle integration. It must not contain feature business logic.

`SoonrApp` creates one live `AppDependencies` value and `RootTabView` passes its
capabilities into feature roots. Previews use `AppDependencies.preview`, which is
backed by in-memory data. Observable global state such as the signed-in session
will be created once here and injected through the SwiftUI environment.

### `Features`

Each product capability owns its views, observable model, and consumer-facing
service interfaces. A feature begins with only the files it needs.

Typical feature contents:

```text
Search/
  SearchView.swift       presentation and user interaction
  SearchModel.swift      screen state and async orchestration
  TitleSearching.swift   capability required by the model
```

Capability protocols live with the feature that consumes them, not beside the
infrastructure that implements them, and stay as narrow as the store that uses
them. Notifications is the worked example: `NotificationsReading`,
`NotificationPreferencesProviding`, `DeviceRegistering`, and
`NotificationStreaming` are four protocols over one service, so each store
depends only on what it calls and each test stub implements only that. One
protocol carrying all of it made every stub implement methods it never used,
and every new endpoint break all of them.

Small reusable row views may remain in their feature. They move to the design
system only after reuse is demonstrated.

### `DesignSystem`

Owns reusable presentation: `TitleArtwork`, `TitleRow`, `ReleaseBadge`, and
`PlaceholderScreen`. These views take values and closures, never models or
capabilities, so any feature can use them. Pure text helpers that shape what a
component renders, such as `TitleRowText`, live beside their component and are
unit tested directly.

A view earns a place here once a second feature needs it; until then it stays
private to its feature.

### `Infrastructure`

Owns technical integrations such as HTTP, Supabase Auth, secure persistence,
logging, and later generated OpenAPI code. Infrastructure returns typed values;
it does not make presentation decisions.

The API layer is responsible for:

- base URLs and environment configuration
- request construction, headers, and timeouts
- bearer-token attachment for authenticated routes
- HTTP status validation and response decoding
- transport-level error normalization

`APIClient` implements that shared request behavior, including turning a
cancelled `URLSession` request into `CancellationError`. Its transport is an
injectable closure so tests exercise request construction and decoding without
a network. `SoonrAPI` holds endpoint-specific paths and response wrappers.

The iOS client calls `apps/api` for application data. It never calls RAWG or the
Supabase database directly. Supabase on iOS is limited to authentication and
session management.

#### Realtime

`NotificationsSocket` is the client half of `GET /notifications/stream`. Its
transport sits behind `WebSocketChannel`, so the handshake, reconnect, and
heartbeat logic above it is tested without a server.

Two properties of that endpoint shape everything above it:

- **It authenticates by message, not by header.** A new connection has five
  seconds to send `{"type":"auth","accessToken":…}` before the server closes it
  with 4401, so the token is fetched per attempt and a reconnect after a long
  backoff carries a fresh one rather than a captured stale one.
- **It pushes invalidations, not records.** A change arrives as
  `{"type":"notifications.changed","scope":"records"}` carrying no payload. The
  client answers by refetching, which means no merge logic, no dedupe against a
  push describing the same change, and a missed event costing latency rather
  than correctness. A `preferences` event is the exception: it carries the new
  copy when the server has a readable one.

A socket idling behind NAT is dropped without either end being told, and this
stream is quiet by nature, so a ping on a timer turns a dead connection into a
failed send that the existing reconnect answers.

### `Shared`

Contains types already used by multiple features, plus small platform-neutral
helpers. Views belong in `DesignSystem`; `Shared` holds models and logic.
`Shared` is not a miscellaneous folder: a type stays inside its feature until a
real second consumer needs it.

```text
Shared/
  Models/            TitleSummary, TitleDestination, FailureReason
  Previews/          in-memory doubles, DEBUG only
  ReleaseDateText    formatting used by several features
```

Everything in `Previews/` is wrapped in `#if DEBUG`, as is every `#Preview`
block that uses it. They were compiled into the release binary until that was
noticed, and only a Release build finds such a site — a Debug build compiles
both halves, so it cannot.

API response types may initially double as application models when their shapes
are identical. Introduce explicit DTO-to-domain mapping only when the API shape
and application needs diverge.

### `SoonrTests`

Mirrors production feature ownership. Unit tests use Swift Testing and never
perform live network requests. Feature models receive fakes through their small
capability protocols. UI tests, when added, use XCTest for a few critical flows.

## State ownership

Use the narrowest state mechanism that fits:

| State | Owner | Swift mechanism |
| --- | --- | --- |
| Temporary UI state | One view | `@State private` |
| Parent-owned editable value | Parent, mutated by child | `@Binding` |
| Feature loading and behavior | Feature model | `@MainActor @Observable` |
| Session or other global state | App root | `@Observable` via environment |
| Small persisted preference | SwiftUI/UserDefaults | `@AppStorage` |
| Structured offline data | Persistence layer | SwiftData when required |

Server responses remain feature-local unless multiple screens genuinely share
their lifetime. Avoid a single app-wide store containing every feature's state.

**The rule that decides it: two screens reading the same server state share one
store.** A feature model owned per screen is right until a second screen reads
the same thing, at which point two copies drift apart and then overwrite each
other. `WatchlistStore`, `NotificationsStore` and
`NotificationPreferencesStore` are each at the root for that reason and no
other; everything else stays per-screen.

### Why not a state-management library

`@Observable` in the environment is Apple's own answer, and the Observation
framework tracks reads per property, so a view re-renders only for the fields
it actually reads. That is the granularity an atom library buys elsewhere, and
it is already in the language here.

The Composable Architecture is the reducer-and-store option, and it earns its
learning curve and its dependency when state must be exactly answerable —
complex undo, multiplayer, intricate navigation. This app is a list, a detail
screen and some switches.

Point-Free's `swift-sharing` is the closest thing to atoms: one property
wrapper usable from views, models and UIKit alike, with persistence backends.
Its two advantages are persistence and working outside SwiftUI. Our persistence
is a server API, and there is no UIKit here.

Revisit if the app grows genuinely intricate navigation or undo, or needs state
shared with a widget or an app extension — that last one is what would make
`swift-sharing` pay for itself.

## Concurrency

- Feature models that update presentation state are isolated to `MainActor`.
- Network operations use `async`/`await` and must respect task cancellation.
- SwiftUI `.task(id:)` owns query-driven work such as debounced search.
- Views do not launch detached work or mutate observable state from background
  actors.

## Configuration and security

Debug, Staging, and Release each have an `.xcconfig` in `Configurations/`,
which fills `Info.plist` keys the app reads at launch. Debug keeps the Xcode
scheme environment override for pointing at a local API.

A Release build must not silently fall back to staging, so `Release.xcconfig`
carries no API host until production exists, and the app stops at launch with a
message naming the setting to fix. Secrets never live in a committed
`.xcconfig`: `Local.xcconfig` is gitignored and CI injects it.

Only public configuration belongs in the application bundle. Supabase secret or
service-role keys must never be added to the iOS target. Authentication tokens
are supplied by the Supabase session and are not manually persisted in
`UserDefaults`.

## API contract evolution

Search and title details use small handwritten Codable contracts. Title details
decode `TitleSummary` from the same flat payload instead of duplicating fields.

Swift OpenAPI Generator was evaluated against `apps/api/openapi.generated.json`
when title details became the second endpoint, and deferred:

- it adds three Swift packages (generator, runtime, URLSession transport) and a
  build plugin, the project's first dependencies
- the spec inlines every schema and has no `components`, so generated types are
  anonymous, operation-scoped payloads that would still need mapping into
  `TitleSummary` and `TitleDetails`
- two read-only endpoints are cheap to maintain by hand, with decoding tests
  built from real payloads

Revisit when the API publishes named component schemas or when the
authenticated watchlist and notification endpoints arrive. A lighter
alternative is a drift check that decodes spec examples in tests.

Feature models keep depending on narrow protocols even if their live
implementation later uses a generated client.

## Paging

`Page` is one response's worth; `PagedList` is the accumulated pages, as a
plain value with no notion of any feature. Both lists use it, and the rules
that matter are cost rules:

- membership is a `Set`, so loading page *n* does not cost *n* passes over what
  is already held
- nothing rebuilds the array wholesale — `List` diffs on identity, so appending
  costs work for new rows only, while a freshly built array is a full diff and
  a lost scroll position
- no `.id()` on a `ForEach` child, ever: it makes `List` build every row
  eagerly, which is the entire cost of paging paid at once

**Identity is the list's, not the domain's.** `PagedList` dedupes on
`Identifiable`. A watchlist entry is identified by the entry but removed by the
title it holds, and a title saved locally carries a stand-in id until the
server answers — so the store bridges that gap rather than the value type
guessing at it. Removal takes a predicate for the same reason.

**Cursors are anchored to a row's own values, not to an offset.** Deleting the
row a cursor was made from does not move where the next page starts, and rows
arriving at the top do not shift a deeper cursor. That is what lets a realtime
change reload only the first page and leave `nextCursor` alone.

**Ordering is an assumption, not a given.** Putting new rows on top is correct
only while the server's order is newest-first, which it is for both lists
today. A sort option would invalidate it — see the roadmap, which records what
breaks before anyone builds it.

## Decision record: counting realtime echoes

**Context.** `notification_records_realtime_trigger` is an `after insert or
update … for each row` trigger, and an update to `read_at` notifies. Reading a
notification therefore comes back to the device that read it as news that
notifications changed. Answering every event with a refetch cost two requests
per tap and two per row for marking everything read — forty requests for twenty
unread notifications, all for changes the screen had already applied.

**Decision.** `NotificationsStore` counts the events its own writes are owed and
counts incoming events off against that budget, refetching only what is left
over. The count is exact rather than time-based because
`markAllNotificationsRead` returns how many rows the server changed, which is
how many events the per-row trigger produces. Events are also collapsed, so a
burst costs one refetch whoever caused it.

**Consequences, and what breaks it.** The counts balance, so a change from
elsewhere landing inside a burst of ours is still answered exactly once. But the
budget assumes **one event per changed row** and **1:1 delivery**:

- changing that trigger to `for each statement`, or notifying on columns other
  than `read_at`, silently breaks the accounting
- so would a lossy buffering policy on the event stream, which is why
  `AsyncStream` is left unbounded here rather than `.bufferingNewest(1)`

A budget left standing by an event that never arrives expires after ten seconds,
so a mismatch degrades to one stale list rather than a permanently deaf client.
`NotificationsStoreTests` covers each of these paths, and each test was checked
by breaking the code it covers.

## Architecture checkpoints

Revisit structure only when evidence warrants it:

- A second endpoint needs the same request behavior: extract the request core
  (done: `APIClient`).
- A store depends on a protocol it only partly calls: split the protocol
  (done: notifications, four capabilities over one service).
- A second feature needs a UI component: consider the design system
  (`TitleArtwork` is shared by search rows and title details, and
  `ReleaseDateText` by both features).
- Image sizing moves server-side when another client needs it. Today
  `TitleArtwork` rewrites RAWG CDN URLs to a supported resize width (420 for
  rows, 1280 for heroes) because originals can be 4K JPEGs.
- API and application models diverge: add an explicit mapper.
- Multiple features share mutable lifetime: define a deliberate shared owner.
- Team ownership or build times become painful: consider Swift packages.

These checkpoints allow the architecture to grow with the product without a
large speculative framework or later rewrite.
