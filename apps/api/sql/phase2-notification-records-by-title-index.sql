-- Asking what one game has said.
--
-- The list groups notifications by the game they are about, and a group can
-- only count what has been paged in — so it says "+2" and becomes "+5" three
-- pages later. Asking the server about one game instead is the only way for
-- that number, and the sheet behind it, to be right.
--
-- Without this index that question scans every notification the user has, in
-- creation order, discarding almost all of them. The columns are the same
-- ordering the list already uses, so a page of one game's notifications comes
-- straight off the index.

create index if not exists notification_records_user_title_idx
  on public.notification_records (user_id, destination_title_id, created_at desc, id desc);
