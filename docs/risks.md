# Risks, ranked

This is a report only; nothing here has been fixed. Onboarding, 2026-09-27, `origin/dev` at
`045ffb4`.

**How to read the evidence column:**
- **live**: confirmed read-only against `soonr-staging` (Supabase advisors plus catalog queries).
- **code**: read from source.
- **inferred**: follows from the code but hasn't been observed running.

Prod (`soonr`) is paused and could not be checked.

## Data exposure and auth (fix first)

| # | Risk | Evidence | Why it matters |
|---|---|---|---|
| 1 | **`list_watchlist_items_page(p_user_id, …)` is `SECURITY DEFINER`, executable by `anon`, and trusts the `p_user_id` it's given** | live: advisor `0028`; `has_function_privilege('anon')` = true. code: `supabase/migrations/20260404193000_add_watchlist_query_to_rpc.sql:14` | Anyone with the publishable key, which ships in every app, can page through any user's watchlist at `/rest/v1/rpc/list_watchlist_items_page`. This is an IDOR. |
| 2 | **`generate_release_approaching_notifications` is `SECURITY DEFINER` and executable by `anon`** | live: advisor `0028`. code: `20260403091359_…sql:10` | Unauthenticated writes: anyone can trigger notification fan-out repeatedly. |
| 3 | **Six tables are created with RLS off and no `REVOKE`** (`auth_user_identities`, `user_profiles`, `user_follows`, `watchlist_events`, `catalog_sync_*`) | code: `20260421110000`, `20260421143000`, `20260414113000`. live: not applied on staging yet | The first time these migrations are applied to a Supabase project, which ADR 6 now requires, every user's email becomes readable, and profiles and follows become writable, through PostgREST. **Must be fixed in the migration before it is applied.** |
| 4 | **Live schema drift:** the DBs don't match any source | live: `watchlist_items` has `security_invoker=on` on staging, but no migration sets it. code: `apps/api/sql` is applied by hand; the migration-only tables exist in Railway by an unknown route | No one can rebuild or audit prod from the repo. A security fix made by hand can be lost on the next reset. |
| 5 | **The legacy edge function is still deployable and public** (`verify_jwt = false`, service-role key, CORS `*`) | code: `supabase/config.toml:23`, `functions/api/index.ts:61`, `handlers/detail.ts:34-45` | `GET /titles/rawg:<any>` fetches from RAWG and upserts into `titles` without auth, which burns RAWG quota and lets anyone grow the table. Whether it is deployed on staging or prod is not verified. |
| 6 | **Email enumeration, plus a full `listUsers` scan on `GET /auth/email-availability`** | code: `apps/api/src/lib/auth.ts:124-153` | Unauthenticated. It reveals which emails have accounts, and each cache miss pages through every auth user, which is a DoS amplifier. |
| 7 | **No rate limiting anywhere in `apps/api`** | code: no `@fastify/rate-limit` | Unlimited sign-up, email checks, WebSocket auth attempts, and `GET /titles?forceRefresh=1`. The last always calls RAWG and then enriches each result, which exhausts the quota and costs money. |
| 8 | **Sign-up auto-confirms email, and passwords only need 8 characters** | code: `lib/auth-service.ts:146`, `schemas/auth.ts:14`. live: advisor "Leaked password protection disabled" | Anyone can create accounts for emails they don't own. Breached passwords are accepted. |
| 9 | **Two sign-up paths with different results** | code: iOS → `POST /auth/sign-up`; mobile and web → `supabase.auth.signUp` | Mobile and web users get no profile and no identity row, so the social features break for them. |
| 10 | **`notification_records` update policy lets a user change any column of their own rows** | code: `20260402110000_create_notifications.sql` | Users can rewrite their notification text or payload through PostgREST. Low impact, but read-only-except-`read_at` is the intent. |
| 11 | **Followers, following and friends are listable for anyone**, with no visibility check | code: `apps/api/src/lib/social/service.ts:274-318` | Leaks the social graph even when the watchlist is private. |
| 12 | **500 responses echo `error.message`** | code: `routes/shared.ts:70`, `functions/api/index.ts:139` | Leaks SQL and internal details to clients. |

## Supply chain and pipeline

| # | Risk | Evidence |
|---|---|---|
| 13 | GitHub Actions are pinned to tags, not SHAs. The Supabase CLI and EAS use `latest` | `.github/workflows/*` |
| 14 | No `minimumReleaseAge` in `pnpm-workspace.yaml` (it does use `allowBuilds`) | `pnpm-workspace.yaml` |
| 15 | No `osv-scanner` or `semgrep` in CI | `.github/workflows/*` |
| 16 | RAWG key is sent as a URL query parameter | `apps/api/src/lib/rawg.ts:136` (a RAWG API constraint, so keep URLs out of logs) |

No live secrets were found in tracked files or in git history. `.env*` and `Local.xcconfig` are
gitignored.

## Checks that are red or missing

| # | Gap | Evidence |
|---|---|---|
| 17 | `check:api-types` fails because the generated client types are stale, so `verify:pre-push` fails. It isn't in CI | `packages/api-client/src/generated/openapi.ts` (no `PUT /profile/me`) |
| 18 | The worktree `core.hooksPath` points at a missing directory, so pre-push doesn't run in worktrees | `git config core.hooksPath` |
| 19 | `apps/api` tests need `DATABASE_URL` set even though they don't connect | `apps/api/src/lib/env.ts:92` |
| 20 | Deno tests for the edge function fail and are wired to nothing | `packages/types/src/notifications.ts:1` extensionless import |
| 21 | **No tests at all** for mobile, web and `packages/*`. **No e2e** anywhere. No authorization matrix, login-abuse or data-exposure test gates | test scripts are missing |
| 22 | iOS test runs are hosted in the app and launch `AppDependencies.live()`, so they can reach staging and read the simulator Keychain | `SoonrApp.swift`; no XCTestConfiguration guard |

## Scale (only from reading the code; `scale-review` not run as a gate)

| # | Risk | Evidence |
|---|---|---|
| 23 | No test runs any list or query at ≥10k rows. Watchlist and notifications use cursor pages; no deep-page timing | the `apps/api` tests are unit-level |
| 24 | Search enrichment is fire-and-forget, once per RAWG result, with no concurrency cap | `lib/search/service.ts:52` |
| 25 | `limit`/`page` go through `parseInt` without schema bounds on some routes (clamped later) | `apps/api/src/routes/*` |

## Accessibility (not assessed)

`a11y-check` was **not run**. There's no axe or keyboard test on web, and no VoiceOver pass
recorded for iOS or mobile. This needs its own ticket once it's decided which clients ship.

## Ranking rationale

Data exposure comes first because it is what breaches real apps (PLAYBOOK §9).

- **#1–2** are exploitable today on staging.
- **#3** becomes exploitable the moment ADR 6 is carried out, so it has to go into that work, not
  after it.
- **#4** is ranked with them because without a reproducible schema none of the other fixes can
  be verified.
