# Understanding log

A record of what the human could explain from memory, used to decide where to slow down. It's
not a grade.

## 2026-09-27: onboarding, against docs/MAP.md

| Item | Result | Notes |
|---|---|---|
| What the app does | ✅ | Game search, watchlist, release notifications, accounts, social layer (partly built). |
| Map: the search request path | partial | Knew there's a search API with scored ranking. Missed that the DB is checked first, with RAWG as fallback and cache fill, and that the app never calls RAWG. Walked through it. |
| Key rule: who can see a watchlist | partial, after one redo | First answer: "at the account level?" After the walkthrough: "the API only includes the data if it's yours", which is correct. Didn't yet explain why the legacy Supabase RPC bypasses that: it's called directly with the public key, is `SECURITY DEFINER`, and trusts `p_user_id`. |
| Debugging: missing release notification | partial | Right first move: check the Postgres records. Thought the socket was a suspect. Corrected: the chain is generate cron → `notification_records` → `deliver:push` sets `pushed_at` → `device_tokens`. The socket is only the in-app live update. |

**Two to watch:** the backend topology (which DB and which server are live), and the difference
between API-level and DB-level authorization. The first security ticket touches exactly this, so
its explain-back should re-check it.

The human's own view: "I can explain the overall idea, but it's well documented as is." The
docs describe the system, but they can't answer a debugging question for you under pressure.
