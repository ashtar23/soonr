import { getPostgresPool } from "./postgres";

export interface PendingReleaseDateChange {
  titleId: string;
  // The date before the first unprocessed change for this title.
  previousReleaseDate: string | null;
  // The date after the last one.
  nextReleaseDate: string | null;
  changeIds: number[];
}

export interface ReleaseDateChangeStore {
  pendingChanges: () => Promise<PendingReleaseDateChange[]>;
  notifyWatchers: (change: {
    titleId: string;
    previousReleaseDate: string;
    nextReleaseDate: string;
  }) => Promise<number>;
  markProcessed: (changeIds: number[]) => Promise<void>;
}

export interface ReleaseDateChangeSummary {
  titlesConsidered: number;
  titlesNotified: number;
  insertedRecordCount: number;
}

/**
 * Tells watchers when a game they are following moves.
 *
 * Changes are collapsed per title before anything is sent. A provider that
 * moves a date and moves it back leaves two rows saying so, and the reader
 * cares about neither — the date they were told is the date it still is. Net
 * of the two is no change, and no change is not news.
 *
 * That is also why there is no threshold on how far a date has to move. A
 * day's slip is real news and a wobble is no news, and collapsing tells them
 * apart without having to guess a number that would be wrong for one of them.
 *
 * A date appearing or disappearing is left alone. "Announced" and "no longer
 * dated" are different sentences from "moved", and a notification that says
 * the wrong one is worse than one that never arrives.
 */
export async function generateReleaseDateChangeNotifications(deps: {
  store: ReleaseDateChangeStore;
}): Promise<ReleaseDateChangeSummary> {
  const pending = await deps.store.pendingChanges();

  let titlesNotified = 0;
  let insertedRecordCount = 0;

  for (const change of pending) {
    const move = moveWorthTelling(change);

    if (move) {
      insertedRecordCount += await deps.store.notifyWatchers({
        titleId: change.titleId,
        ...move,
      });
      titlesNotified += 1;
    }

    // Processed either way: a change nobody needed telling about is still
    // handled, and leaving it would mean deciding again every run.
    await deps.store.markProcessed(change.changeIds);
  }

  return {
    titlesConsidered: pending.length,
    titlesNotified,
    insertedRecordCount,
  };
}

/**
 * The pair to tell someone about, or nothing.
 *
 * Returns the pair rather than answering yes or no, so the caller holds two
 * dates it knows are there instead of two it has to check again.
 */
function moveWorthTelling(
  change: PendingReleaseDateChange,
): { previousReleaseDate: string; nextReleaseDate: string } | null {
  const { previousReleaseDate, nextReleaseDate } = change;

  if (
    previousReleaseDate === null ||
    nextReleaseDate === null ||
    previousReleaseDate === nextReleaseDate
  ) {
    return null;
  }

  return { previousReleaseDate, nextReleaseDate };
}

export const postgresReleaseDateChangeStore: ReleaseDateChangeStore = {
  async pendingChanges() {
    const pool = getPostgresPool();
    const result = await pool.query<{
      title_id: string;
      previous_release_date: string | null;
      next_release_date: string | null;
      change_ids: number[];
    }>(
      `
        select
          title_id,
          -- The date before the first of them, and after the last: the net of
          -- everything that has happened since anyone was told.
          (array_agg(previous_release_date order by changed_at, id))[1]
            as previous_release_date,
          (array_agg(next_release_date order by changed_at desc, id desc))[1]
            as next_release_date,
          array_agg(id order by id) as change_ids
        from public.title_release_date_changes
        where processed_at is null
        group by title_id
      `,
    );

    return result.rows.map((row) => ({
      titleId: row.title_id,
      previousReleaseDate: toDateString(row.previous_release_date),
      nextReleaseDate: toDateString(row.next_release_date),
      changeIds: row.change_ids,
    }));
  },

  async notifyWatchers({ titleId, previousReleaseDate, nextReleaseDate }) {
    const pool = getPostgresPool();
    const result = await pool.query<{ inserted_record_count: number }>(
      `
        with event as (
          insert into public.notification_events (
            id, title_id, event_type, event_version, event_key, occurred_at, payload
          )
          select
            'notification-event:' || $4::text,
            $1::text,
            'release_date_changed',
            1,
            $4::text,
            timezone('utc', now()),
            jsonb_build_object(
              'previousReleaseDate', $2::text,
              'nextReleaseDate', $3::text
            )
          on conflict (event_key) do nothing
          returning id
        ),
        resolved as (
          select id from event
          union all
          select id from public.notification_events
          where event_key = $4::text and not exists (select 1 from event)
        ),
        watchers as (
          select w.user_id, t.name, t.cover_image_url
          from public.watchlists w
          join public.titles t on t.id = w.title_id
          left join public.notification_preferences p on p.user_id = w.user_id
          where w.title_id = $1::text
            -- No row means the defaults, which have this on.
            and coalesce(p.release_date_changed_enabled, true)
            and coalesce(p.in_app_enabled, true)
        ),
        inserted as (
          insert into public.notification_records (
            id, user_id, event_id, title_id, event_type, destination_kind,
            destination_title_id, title_name, title_artwork_url,
            message, subtitle, payload, created_at
          )
          select
            'notification-record:' || r.id || ':' || w.user_id::text,
            w.user_id,
            r.id,
            $1::text,
            'release_date_changed',
            'title',
            $1::text,
            w.name,
            w.cover_image_url,
            'Release date changed',
            'Now releases ' || trim(to_char($3::date, 'FMMon FMDD, YYYY')),
            jsonb_build_object(
              'previousReleaseDate', $2::text,
              'nextReleaseDate', $3::text
            ),
            timezone('utc', now())
          from watchers w
          cross join resolved r
          on conflict (event_id, user_id) do nothing
          returning 1
        )
        select count(*)::int as inserted_record_count from inserted
      `,
      [
        titleId,
        previousReleaseDate,
        nextReleaseDate,
        eventKey(titleId, previousReleaseDate, nextReleaseDate),
      ],
    );

    return result.rows[0]?.inserted_record_count ?? 0;
  },

  async markProcessed(changeIds) {
    if (changeIds.length === 0) {
      return;
    }

    const pool = getPostgresPool();
    await pool.query(
      `
        update public.title_release_date_changes
        set processed_at = timezone('utc', now())
        where id = any($1::bigint[])
      `,
      [changeIds],
    );
  },
};

/**
 * Both dates, so a game that moves and moves back is two pieces of news rather
 * than one that cannot be told twice.
 */
export function eventKey(
  titleId: string,
  previous: string,
  next: string,
): string {
  return `release_date_changed:${titleId}:${previous}:${next}`;
}

function toDateString(value: string | Date | null): string | null {
  if (value === null) {
    return null;
  }

  return value instanceof Date
    ? value.toISOString().slice(0, 10)
    : String(value).slice(0, 10);
}
