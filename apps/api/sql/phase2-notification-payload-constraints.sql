-- Payload shape, enforced where the data is written.
--
-- `jsonb` accepts any object, so a payload the API cannot serialize was
-- accepted happily on the way in and failed on the way out — taking the whole
-- notifications list down for that user until the row was repaired by hand.
--
-- The API normalizes what it reads, so a row that slipped past can no longer
-- break a response. This stops one being written at all, which is the
-- difference between one rejected insert and a list nobody can load.
--
-- Deliberately checks only the keys a reader depends on. `timingPreset` is not
-- among them: it is optional in the response and nothing renders it, so
-- requiring it here would reject rows that work.

alter table public.notification_events
  drop constraint if exists notification_events_payload_shape_check;

alter table public.notification_events
  add constraint notification_events_payload_shape_check check (
    jsonb_typeof(payload) = 'object'
    and (
      (event_type = 'release_approaching' and payload ? 'targetReleaseDate')
      or (event_type = 'release_date_changed' and payload ? 'nextReleaseDate')
    )
  );

alter table public.notification_records
  drop constraint if exists notification_records_payload_shape_check;

alter table public.notification_records
  add constraint notification_records_payload_shape_check check (
    jsonb_typeof(payload) = 'object'
    and (
      (event_type = 'release_approaching' and payload ? 'targetReleaseDate')
      or (event_type = 'release_date_changed' and payload ? 'nextReleaseDate')
    )
  );
