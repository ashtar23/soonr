# 1. apps/api is the backend

*Inferred from code, confirm or correct.*

**Decision.** All clients talk to one Fastify service in `apps/api`, hosted on Railway (confirmed
by Vlad, 2026-09-27). It reads and writes Postgres directly through a `pg` pool with a privileged
role. The Supabase edge function in `supabase/functions/api` is legacy.

**Evidence.**
- Both TS clients and iOS use one base URL: `EXPO_PUBLIC_API_BASE_URL`, `VITE_API_BASE_URL` and
  `SoonrAPIBaseURL`.
- The routes they call, `POST /notifications/read` and the `/notifications/stream` WebSocket,
  exist only in Fastify.
- The edge function was last changed 2026-04-04. `apps/api` was last changed 2026-09-14.

**Consequences.**
- Authorization is enforced in application code (`WHERE user_id = $1`), not by RLS.
- The root `AGENTS.md` line "Backend is Supabase-first" is out of date.
- The edge function and the Supabase tables are still deployable and publicly reachable, so they
  need to be retired or locked down. See `docs/risks.md`.
