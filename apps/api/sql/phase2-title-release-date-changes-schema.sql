-- A release date moving, remembered.
--
-- `titles` is upserted from three places — filling the search cache, the
-- catalogue sync, and fetching a title's details — and every one of them
-- overwrites `earliest_release_date` with whatever the provider last said. The
-- old value is gone the moment the new one lands, so a date change cannot be
-- noticed after the fact. That is why nothing generates `release_date_changed`
-- notifications: not a missing generator, a missing memory.
--
-- A trigger records it instead of each writer having to, which also means a
-- fourth writer added later is covered without knowing this exists.
--
-- Nothing reads this table yet. It is here to collect real changes so the
-- shape of them can be seen — how often a provider moves a date, and by how
-- much — before anyone is told about one.

create table if not exists public.title_release_date_changes (
  id bigserial primary key,
  title_id text not null references public.titles(id) on delete cascade,
  previous_release_date date,
  next_release_date date,
  changed_at timestamptz not null default timezone('utc', now()),
  -- Set once a generator has fanned this out. Null means nobody has been told.
  processed_at timestamptz
);

-- The generator will read oldest-unprocessed-first.
create index if not exists title_release_date_changes_pending_idx
  on public.title_release_date_changes (changed_at)
  where processed_at is null;

create index if not exists title_release_date_changes_title_idx
  on public.title_release_date_changes (title_id, changed_at desc);

create or replace function public.record_title_release_date_change()
returns trigger
language plpgsql
as $$
begin
  -- `is distinct from` rather than `<>`, so a date appearing or disappearing
  -- counts as a change: null is a real state here, meaning unannounced.
  if new.earliest_release_date is distinct from old.earliest_release_date then
    insert into public.title_release_date_changes (
      title_id,
      previous_release_date,
      next_release_date
    )
    values (
      new.id,
      old.earliest_release_date,
      new.earliest_release_date
    );
  end if;

  return null;
end;
$$;

drop trigger if exists title_release_date_change_trigger on public.titles;

-- Only on update: a title arriving for the first time has not changed, it has
-- been learned.
create trigger title_release_date_change_trigger
after update of earliest_release_date on public.titles
for each row
execute function public.record_title_release_date_change();
