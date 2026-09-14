import { getPostgresPool } from "./postgres";

export interface NotificationRetentionStore {
  // Returns how many rows went.
  deleteReadNotificationsBefore: (params: {
    olderThanDays: number;
  }) => Promise<number>;
  deleteOrphanedEvents: () => Promise<number>;
}

export interface NotificationRetentionSummary {
  olderThanDays: number;
  deletedRecords: number;
  deletedEvents: number;
}

// Long enough that a game's whole run-up — a month of reminders, the release,
// and a while after — is still there to look back on.
export const DEFAULT_RETENTION_DAYS = 180;

/**
 * Removes notifications nobody is going to read again.
 *
 * Nothing has ever deleted one, so the table only grows, and the unread count
 * runs against it on every launch. Growth is slow enough to be invisible and
 * exactly the kind that is cheap to handle now and needs a migration window
 * later.
 *
 * Only read ones. An unread notification is the reader's own unfinished
 * business and is not ours to tidy away, however old it is.
 *
 * Events go when the last record referencing them does. They are shared
 * between the users watching the same game, so one user's tidying must not
 * take another's notification with it — which deleting an event would, since
 * records cascade from it.
 */
export async function pruneNotifications(
  deps: { store: NotificationRetentionStore },
  options: { olderThanDays?: number } = {},
): Promise<NotificationRetentionSummary> {
  const olderThanDays = normalizeRetentionDays(options.olderThanDays);

  const deletedRecords = await deps.store.deleteReadNotificationsBefore({
    olderThanDays,
  });

  // Only worth asking when something was actually removed.
  const deletedEvents =
    deletedRecords > 0 ? await deps.store.deleteOrphanedEvents() : 0;

  return { olderThanDays, deletedRecords, deletedEvents };
}

/**
 * A retention window of zero would delete everything read, which is a
 * plausible typo and an unrecoverable one.
 */
export function normalizeRetentionDays(value: number | undefined): number {
  if (!Number.isFinite(value) || value === undefined) {
    return DEFAULT_RETENTION_DAYS;
  }

  return Math.max(1, Math.floor(value));
}

export const postgresNotificationRetentionStore: NotificationRetentionStore = {
  async deleteReadNotificationsBefore({ olderThanDays }) {
    const pool = getPostgresPool();
    const result = await pool.query(
      `
        delete from public.notification_records
        where read_at is not null
          and created_at < timezone('utc', now()) - ($1::integer * interval '1 day')
      `,
      [olderThanDays],
    );

    return result.rowCount ?? 0;
  },

  async deleteOrphanedEvents() {
    const pool = getPostgresPool();
    const result = await pool.query(
      `
        delete from public.notification_events e
        where not exists (
          select 1 from public.notification_records r where r.event_id = e.id
        )
      `,
    );

    return result.rowCount ?? 0;
  },
};
