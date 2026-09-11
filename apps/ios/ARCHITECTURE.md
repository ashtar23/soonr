# Soonr iOS Architecture

## Purpose

Soonr for iOS is a native SwiftUI client targeting iOS 26. The app is built as
small end-to-end vertical slices while preserving clear ownership boundaries.
This document records the rules that should remain stable as features are added.

The current codebase is a single application target. Folders communicate intent;
they are not separate modules yet. Swift packages should only be introduced when
team ownership, reuse, or build performance gives us a concrete reason.

## Guiding principles

- Build the smallest user-visible flow through UI, state, API, and tests.
- Keep state close to its owner; app-global state must be genuinely global.
- Depend on small capabilities rather than concrete infrastructure.
- Keep network, authentication, persistence, and logging out of SwiftUI views.
- Extract shared code after a second real consumer appears, not in anticipation.
- Prefer Apple frameworks and Swift concurrency before adding dependencies.
- Every completed slice must build, have deterministic tests, and receive a
  simulator smoke test.

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

As shared services appear, `SoonrApp` will create an `AppDependencies` value and
pass dependencies into feature roots. Observable global state such as the signed-
in session is created once here and injected through the SwiftUI environment.

### `Features`

Each product capability owns its views, observable model, and consumer-facing
service interfaces. A feature begins with only the files it needs.

Typical feature contents:

```text
Search/
  SearchView.swift       presentation and user interaction
  SearchModel.swift      screen state and async orchestration
  TitleSearching.swift   capability required by the model, when extracted
```

Small reusable row views may remain in their feature. They move to the design
system only after reuse is demonstrated.

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

The iOS client calls `apps/api` for application data. It never calls RAWG or the
Supabase database directly. Supabase on iOS is limited to authentication and
session management.

### `Shared`

Contains types already used by multiple features, such as `TitleSummary`, plus
small platform-neutral helpers. `Shared` is not a miscellaneous folder. A type
stays inside its feature until a real second consumer needs it.

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

## Concurrency

- Feature models that update presentation state are isolated to `MainActor`.
- Network operations use `async`/`await` and must respect task cancellation.
- SwiftUI `.task(id:)` owns query-driven work such as debounced search.
- Views do not launch detached work or mutate observable state from background
  actors.

## Configuration and security

The current development build defaults to the staging API and supports Xcode
scheme environment overrides. Before production distribution, introduce explicit
Debug, Staging, and Release `.xcconfig` files. A Release build must not silently
fall back to staging.

Only public configuration belongs in the application bundle. Supabase secret or
service-role keys must never be added to the iOS target. Authentication tokens
are supplied by the Supabase session and are not manually persisted in
`UserDefaults`.

## API contract evolution

The first search endpoint uses a small handwritten Codable contract. When the
second substantial endpoint is integrated, evaluate Swift OpenAPI Generator
against `apps/api/openapi.generated.json`. The goal is to remove contract drift
without adding generation complexity before it pays for itself.

Common request behavior should be centralized as endpoints are added. Feature
models should continue depending on narrow protocols even if their live
implementation uses a generated client.

## Architecture checkpoints

Revisit structure only when evidence warrants it:

- A second endpoint needs the same request behavior: extract the request core.
- A second feature needs a UI component: consider the design system.
- API and application models diverge: add an explicit mapper.
- Multiple features share mutable lifetime: define a deliberate shared owner.
- Team ownership or build times become painful: consider Swift packages.

These checkpoints allow the architecture to grow with the product without a
large speculative framework or later rewrite.
