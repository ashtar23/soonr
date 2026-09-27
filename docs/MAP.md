# Soonr codebase map

Mapped from `origin/dev` at `045ffb4` on 2026-09-27, by reading the code and running the repo's
commands. Where older docs (`docs/*.md`, `AGENTS.md`, `apps/ios/ARCHITECTURE.md`, `.planning/`)
disagree with the code, this file follows the code and says so.

## The shape in one picture

```
 apps/ios (Swift)      apps/mobile (Expo)      apps/web (Vite)
      │                     │  @repo/api-client    │  @repo/api-client
      │ REST + WebSocket    │                      │
      └──────────┬──────────┴──────────┬───────────┘
                 │                     │ sign-in / session only
                 ▼                     ▼
        apps/api (Fastify, Railway) ──► Supabase Auth (verify token, admin create user)
          │  pg pool, privileged role
          ▼
        Railway Postgres  ◄── cron services: generate notifications, push delivery (APNs), catalog sync
          ▲
          │ server-side only
        RAWG API

 Legacy, still deployable: supabase/functions/api (Deno) + the Supabase project's own Postgres
```

Clients never call RAWG, never query Supabase tables, and only use Supabase for **auth**.

## Modules

| Module | What it is | Public surface | Depends on |
|---|---|---|---|
| `apps/api` | **The live backend.** Fastify on Node (tsx), hosted on Railway | Routes registered in `src/app.ts:47-55`: system, auth, home, profile, social, titles, notifications, watchlist, and a WebSocket at `/notifications/stream`. Also the scripts `sync:catalog`, `sync:home-discovery`, `generate:release-*`, `deliver:push` and `prune:notifications` | `@repo/types`, `pg`, `@supabase/supabase-js` (auth only), RAWG |
| `apps/ios` | Native SwiftUI app, iOS 17+, Swift 6 strict concurrency | One app target `Soonr` and a test target `SoonrTests` | `supabase-swift` (the `Auth` product only) |
| `apps/mobile` | Expo SDK 55 app with the same features as iOS | Expo Router screens in `src/app`, and features in `src/features/*` | `@repo/api-client`, `@repo/types`, TanStack Query |
| `apps/web` | Vite, React, TanStack Router. **Far behind:** only search, title details and auth | `src/routes` | `@repo/api-client`, `@repo/ui`, `@repo/types` |
| `packages/types` | Domain interfaces, value arrays and zod form schemas | Exports `.` and `./auth` (`signUpCredentialsSchema` is only on `./auth`) | zod |
| `packages/api-client` | Typed fetch client for `apps/api` | `createSoonrApiClient` (`soonr-client.ts:100`), per-resource functions, `ApiClientError`. Types come from generated OpenAPI | `@supabase/supabase-js` (leaks auth into a shared package) |
| `packages/ui` | shadcn and Tailwind v4 components, used by web only | Subpath exports | React (this contradicts `packages/AGENTS.md`) |
| `packages/config` | Env var names | `SUPABASE_*_ENV` (everything else is unused) | none |
| `supabase/functions/api` | **Legacy** Deno edge function (last touched 2026-04-04) | Hand-rolled router in `routing.ts`. `verify_jwt = false` | service-role key |
| `supabase/migrations` | Schema for the Supabase project's Postgres | 16 migrations, the latest dated 2026-04-21 | none |
| `apps/api/sql` | Schema applied **by hand with psql** to Railway Postgres | Push devices, release-date changes, watchlist sort keys, `pg_notify` triggers | none |

### Inside apps/ios

For a React reader: an `@Observable` store is roughly a context provider whose state
re-renders the views that read it. A capability protocol is an interface you'd mock in a test.

- `App/` is the composition root. `AppDependencies.live()` (`AppDependencies.swift:22-49`) builds
  a single `SoonrAPI`, which is handed out as every capability. `SoonrApp.swift:11-148` creates
  the root stores, injects them with `.environment`, and runs the lifecycle tasks (restore
  session, load on sign-in, clear on sign-out, open the socket while active).
- `Features/<Area>/` holds a View, an `@MainActor @Observable` model or store, and narrow
  protocols such as `TitleSearching` and `WatchlistManaging`.
- `Infrastructure/` covers the API (`APIClient`, `SoonrAPI`, `NotificationsSocket`), auth
  (`SupabaseAuthService`), push and logging.
- `DesignSystem/` and `Shared/` hold value-only views and models.

### Inside apps/mobile

Each feature is layered like this: `data-access/` (calls the api-client) → `queries/` and
`mutations/` (TanStack Query) → `hooks/` → `screen-state/derive-*` → `components/`. Realtime
events patch the query cache.

## Data and access model

**Two Postgres databases exist, and neither schema source describes either one completely.**

| Database | Who uses it | Schema comes from | Reached through |
|---|---|---|---|
| Railway Postgres | `apps/api` (live) | `apps/api/sql/*`, applied by hand, **plus** tables that only `supabase/migrations` defines (`user_profiles`, `user_follows`, `auth_user_identities`, `catalog_sync_*`). How those got there is unknown | the `apps/api` pg pool only; there is no PostgREST |
| Supabase `soonr-staging` | Auth for all clients. Tables belong to the legacy edge function | an older subset of `supabase/migrations`. The 2026-04-21 migrations are **not applied**. It has hand-made drift: `watchlist_items` has `security_invoker=on`, which no migration sets | PostgREST with the publishable key, **reachable by anyone** |
| Supabase `soonr` (prod) | Paused | unknown | none while paused |

Decision (Vlad, 2026-09-27): **`supabase/migrations` becomes the source of truth** for the
schema.

**Tables** (see `supabase/migrations`, and `apps/api/sql` for the tables that only exist there):
- `titles`: id `rawg:<n>`, plus release and platform jsonb.
- `watchlists`: `(user_id, title_id)`.
- The view `watchlist_items`.
- Notifications: `notification_preferences`, `notification_events` (unique `event_key`), and
  `notification_records` (`read_at`, `pushed_at`).
- `device_tokens`.
- `title_release_date_changes`, filled by a trigger on `titles`.
- Social: `user_profiles`, `user_follows`, `watchlist_events` (never written).
- `auth_user_identities`.
- `catalog_sync_slices` and `catalog_sync_runs`.

**Where authorization lives:**
- **`apps/api`:** `authenticateRouteRequest` (`routes/shared.ts:14`) calls
  `supabaseAdmin.auth.getUser(token)` on every request. Ownership is then enforced only by
  `WHERE user_id = $1` in each query. There is no RLS in play, and no rate limiting anywhere.
- **Supabase PostgREST:** RLS is on for the six tables that exist on staging. However,
  **SECURITY DEFINER functions are executable by `anon`**, and they bypass it (see
  `docs/risks.md`).

## Key flows

1. **Guest search.**
   - Clients: iOS `SoonrAPI.searchTitles` (`SoonrAPI.swift:22`), and mobile
     `features/search/data-access/search.ts:31` → `api-client/src/search.ts:40`.
   - Server: `GET /titles` (`apps/api/src/routes/titles.ts:22`) → `searchTitles`
     (`lib/search/service.ts:22`) → local trigram/tsvector query (`lib/search/data.ts:31`) →
     `decideSearchExecution` (`policy.ts:22`).
   - If local results fall short, or `forceRefresh=1` is set: RAWG (`lib/rawg.ts:124`) → upsert
     into `titles` (`data.ts:444`) → fire-and-forget detail enrichment (`service.ts:52`).
2. **Title details.** `GET /titles/:id` (`routes/titles.ts:59`) → `lib/titles.ts:10`. This reads
   the DB only, with no RAWG fallback. An optional token adds `isInWatchlist`.
3. **Watchlist add/remove.**
   - `POST /watchlist` (`routes/watchlist.ts:118`) → `titleExists` → upsert
     (`lib/watchlists.ts:122`). `DELETE /watchlist/:titleId` → `lib/watchlists.ts:149`.
   - iOS updates optimistically and rolls back per row (`WatchlistStore.swift:107`).
4. **Notifications.**
   - The Railway cron runs `generate-release-approaching` (`lib/notification-generation.ts:16`)
     and `generate-release-date-changed` (`lib/release-date-change-generation.ts:44`), which
     insert events and records.
   - A `pg_notify` trigger pushes the new rows over the WebSocket.
   - `deliver:push` sends rows where `pushed_at is null` to APNs (`lib/push-delivery.ts`).
   - Mark read: `POST /notifications/read` (`routes/notifications.ts:158`) →
     `lib/notifications.ts:391`, scoped to the user.
5. **Sign-up and sign-in.**
   - **iOS sign-up:** checks availability, then `POST /auth/sign-up` (`routes/auth.ts:58`) →
     `lib/auth-service.ts:94`, which admin-creates a confirmed user and writes the identity and
     profile rows.
   - **Web and mobile sign-up:** call `supabase.auth.signUp` directly. No profile or identity
     row is created: two paths with different outcomes.
   - **Sign-in, all clients:** directly against Supabase Auth.

## Commands (run 2026-09-27, pnpm 11.8.0, Node 24)

| Command | Result |
|---|---|
| `pnpm lint` | pass |
| `pnpm check-types` | pass |
| `pnpm build` (web only) | pass |
| `pnpm --filter api test` | pass (137 tests), **but only with CI's placeholder `DATABASE_URL`**; without it, 10 files crash on import |
| `pnpm check:api-types` | **fail**: `packages/api-client/src/generated/openapi.ts` is stale (missing `PUT /profile/me`). This makes `verify:pre-push` fail, and CI doesn't run it |
| `deno test supabase/functions/api` | **fail**: extensionless imports from `packages/types`. No script or CI job runs it |
| `pnpm test:backend-contracts` | not run: needs a live Supabase and secrets, and writes rows |
| iOS `Scripts/lint.sh`, `xcodebuild test` | not run here (they replace the app on your simulator). CI runs them in `ios-ci.yml` |

These have **no tests at all:** mobile, web, `packages/*`. There is **no e2e** anywhere.

## Open questions

- Swift (`apps/ios`) vs Expo (`apps/mobile`): will both ship? *Undecided (Vlad, 2026-09-27).*
  Today they are full duplicates with no shared code, and mobile is ahead on watchlist sort,
  search and offline.
- How did `user_profiles` and the other migration-only tables get into Railway Postgres?
- Is the legacy edge function still deployed and reachable on staging and prod?
- Is the web app still a product, or a leftover?

## Where the old docs are wrong

- **Root `AGENTS.md` and `supabase/AGENTS.md`:** they say "Backend is Supabase-first" and treat
  the edge function as the backend. The live backend is `apps/api`.
- **`docs/backend-migration-plan.md:159-167`:** it describes
  `EXPO_PUBLIC_HOME_API_BASE_URL`. The code uses a single `EXPO_PUBLIC_API_BASE_URL`.
- **`apps/web/AGENTS.md:10`:** it names `src/App.tsx`, which doesn't exist.
- **`apps/ios/ARCHITECTURE.md`:** several sections are stale.
  - Global state "will be created", but it exists.
  - The DesignSystem list is out of date.
  - The Codable/OpenAPI section still says "first dependency".
  - It promises XCTest UI tests, but there are none.
- **`apps/ios` README:** it suggests `SOONR_API_HOST = 127.0.0.1:3001`, but the scheme is fixed
  to `https`, so that override doesn't work.
- **`Dockerfile.api:1`:** it says Coolify, but hosting is Railway.
