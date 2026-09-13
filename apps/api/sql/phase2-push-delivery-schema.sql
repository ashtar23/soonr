-- When a notification was handed to APNs.
--
-- Delivery reads records that have none, so a run that is repeated — a retry,
-- an overlapping schedule, a manual invocation — cannot send the same
-- notification twice.
alter table public.notification_records
  add column if not exists pushed_at timestamptz;

-- The delivery query looks for unsent, unread records in creation order.
create index if not exists notification_records_pending_push_idx
  on public.notification_records (created_at)
  where pushed_at is null and read_at is null;
