# Soonr glossary

Terms as the code uses them. Types live in `packages/types/src` unless noted.

- **Title**: a game record (`kind: "game"`, `source: "rawg"`). Its id is `rawg:<rawgId>`. Defined
  as `TitleSummary` / `TitleDetails` in `titles.ts`.
- **PlatformRelease**: the release date for one platform. A title has several; the
  **earliestReleaseDate** is the minimum of them.
- **ReleaseDatePrecision**: how exact a release date is: `day | month | year | unknown`. There is
  no release-status enum. "TBA" is only UI formatting.
- **Search served-by**: where a search result came from, either `local-cache` (our DB) or
  `rawg-refresh` (fetched from RAWG and cached). Reported together with a **decision reason**
  (such as `local_sufficient` or `provider_fetch_failed`) and an **intent** (`broad` or
  `specific`). Defined in `search-contract.ts`.
- **forceRefresh**: a search flag that skips the local cache and always calls RAWG. Mobile
  exposes it as a developer toggle.
- **Watchlist / WatchlistItem**: the titles a user saves: a title, its releases, and `addedAt`.
  - Lists use cursor pages and can be filtered with `query`.
  - **WatchlistSort** is `added | release | name` × `asc | desc`.
- **Home discovery**: the three home rails, `upcoming`, `latest` and `popular`, each paged
  separately. Defined in `apps/api/src/lib/contracts.ts`.
- **Notification event**: one fact about a title, deduplicated by `event_key`. There are two
  **NotificationEventType**s:
  - `release_date_changed` (its payload has the previous and next dates)
  - `release_approaching` (its payload has the target date and a timing preset)
- **Notification record**: one event delivered to one user. `read_at` marks it read and
  `pushed_at` marks it sent to APNs.
- **Timing preset**: when a `release_approaching` notification fires: `on_day`,
  `hours_24_before`, `days_7_before` or `days_30_before`.
- **Channel**: where a notification goes, either `inApp` or `push`.
- **Notification preferences**: per user, which event types, presets and channels are on.
- **Device token**: an APNs token registered to a user. Stored with the push environment read
  from the provisioning profile.
- **Profile**: `username`, `displayName`, `avatarUrl`, `bio`. It exists only in `apps/api`
  schemas, not in `@repo/types`.
- **Watchlist visibility**: who can see a user's watchlist: `private | friends | public`.
- **Follow / Friend**: a follow is one-way. A friend is a mutual follow.
- **Catalog sync**: the scripts that pre-fill `titles` from RAWG in slices (`catalog_sync_slices`
  and `catalog_sync_runs`).
