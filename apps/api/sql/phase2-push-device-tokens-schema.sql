-- Devices that have asked to be sent notifications.
--
-- The token is the primary key rather than (user_id, token): a token
-- identifies one install of the app on one device, so when a second account
-- signs in there, the row moves to them. Keyed the other way, the device would
-- keep receiving the previous account's notifications.
create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null,
  platform text not null,
  -- A token minted by a development build is only deliverable through the APNs
  -- sandbox, and a TestFlight or App Store one only through production. The
  -- sender picks the host from this.
  environment text not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint device_tokens_platform_check check (platform in ('ios')),
  constraint device_tokens_environment_check check (
    environment in ('sandbox', 'production')
  )
);

create index if not exists device_tokens_user_id_idx
  on public.device_tokens (user_id);
