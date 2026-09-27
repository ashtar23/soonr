# 6. supabase/migrations is the schema source of truth

*Decided by Vlad, 2026-09-27.* This replaces what the code shows today, where the schema is split
between `supabase/migrations` and `apps/api/sql` (applied by hand with psql).

**Consequences.**
- The `apps/api/sql` pieces must be folded into migrations: `device_tokens`,
  `title_release_date_changes`, the watchlist sort-key triggers, the `pg_notify` triggers and
  `pushed_at`.
- The migrations must then be applied to every live database through a pipeline, not by hand.
- The hand-made drift already on the live databases (e.g. `watchlist_items`
  `security_invoker=on` on staging) must be captured in a migration.
