import { notificationTimingPresetValues } from "@repo/types";
import type {
  NotificationPreferences,
  NotificationPayload,
  NotificationRecord,
  NotificationTimingPreset,
  UpdateNotificationPreferencesInput,
} from "@repo/types";

import type {
  MarkAllNotificationsReadResult,
  MarkNotificationReadResult,
  NotificationPreferencesResult,
  NotificationRecordListResult,
  NotificationUnreadCountResult,
} from "./contracts";
import { getPostgresPool } from "./postgres";

type NotificationUnreadCountRow = {
  unread_count: number | string;
};

type NotificationRecordRow = {
  id: string;
  title_id: string;
  event_type: NotificationRecord["eventType"];
  destination_kind: NotificationRecord["destinationKind"];
  destination_title_id: string;
  title_name: string;
  title_artwork_url: string | null;
  message: string;
  subtitle: string | null;
  // `jsonb` accepts any object, so this is what the column actually holds:
  // something unverified, normalized before it reaches a response.
  payload: unknown;
  created_at: string;
  read_at: string | null;
};

type NotificationPreferencesRow = {
  in_app_enabled: boolean;
  push_enabled: boolean;
  release_date_changed_enabled: boolean;
  release_approaching_enabled: boolean;
  timing_presets: string[];
  updated_at: string;
};

const DEFAULT_PAGE_LIMIT = 20;
const MAX_PAGE_LIMIT = 50;
const VALID_TIMING_PRESETS: NotificationTimingPreset[] = [
  "on_day",
  "hours_24_before",
  "days_7_before",
  "days_30_before",
];
const DEFAULT_NOTIFICATION_PREFERENCES: NotificationPreferences = {
  channels: {
    inApp: true,
    push: false,
  },
  events: {
    releaseDateChanged: true,
    releaseApproaching: true,
  },
  timingPresets: ["on_day"],
  updatedAt: new Date(0).toISOString(),
};

export interface ListNotificationsParams {
  readonly cursor?: string;
  readonly limit?: number;
  // Narrows to what has not been read. Paging still works: the cursor
  // compares a row's own timestamp and id, so it means the same thing
  // whichever rows are being skipped.
  readonly unreadOnly?: boolean;
}

export async function getNotificationUnreadCount(
  userId: string,
): Promise<NotificationUnreadCountResult> {
  const pool = getPostgresPool();
  const result = await pool.query<NotificationUnreadCountRow>(
    `
      select count(*)::int as unread_count
      from notification_records
      where user_id = $1::uuid
        and read_at is null
    `,
    [userId],
  );

  const unreadCount = Number(result.rows[0]?.unread_count ?? 0);
  return { unreadCount: Number.isFinite(unreadCount) ? unreadCount : 0 };
}

export async function listNotificationRecords(
  userId: string,
  params: ListNotificationsParams,
): Promise<NotificationRecordListResult> {
  const pageLimit = normalizeLimit(params.limit);
  const decodedCursor = params.cursor ? decodeCursor(params.cursor) : null;
  const pool = getPostgresPool();

  // Covered by notification_records_user_unread_idx, a partial index whose
  // columns are this query's order, so narrowing costs nothing.
  const unreadWhere = params.unreadOnly ? "and read_at is null" : "";

  let values: unknown[] = [userId, pageLimit + 1];
  let paginationWhere = "";

  if (decodedCursor) {
    values = [userId, decodedCursor.createdAt, decodedCursor.id, pageLimit + 1];
    paginationWhere = `
      and (
        created_at < $2::timestamptz
        or (created_at = $2::timestamptz and id < $3::text)
      )
    `;
  }

  const limitParamIndex = decodedCursor ? 4 : 2;
  const result = await pool.query<NotificationRecordRow>(
    `
      select
        id,
        title_id,
        event_type,
        destination_kind,
        destination_title_id,
        title_name,
        title_artwork_url,
        message,
        subtitle,
        payload,
        created_at,
        read_at
      from notification_records
      where user_id = $1::uuid
      ${unreadWhere}
      ${paginationWhere}
      order by created_at desc, id desc
      limit $${limitParamIndex}
    `,
    values,
  );

  const rows = result.rows;
  const items = rows.slice(0, pageLimit).map(mapNotificationRecord);
  const nextCursor =
    rows.length > pageLimit
      ? encodeCursor(rows[pageLimit - 1]!.created_at, rows[pageLimit - 1]!.id)
      : null;

  return { items, nextCursor };
}

export async function getNotificationPreferences(
  userId: string,
): Promise<NotificationPreferencesResult> {
  const pool = getPostgresPool();
  const result = await pool.query<NotificationPreferencesRow>(
    `
      select
        in_app_enabled,
        push_enabled,
        release_date_changed_enabled,
        release_approaching_enabled,
        timing_presets,
        updated_at
      from notification_preferences
      where user_id = $1::uuid
      limit 1
    `,
    [userId],
  );

  const row = result.rows[0];
  if (!row) {
    return {
      preferences: { ...DEFAULT_NOTIFICATION_PREFERENCES },
    };
  }

  return {
    preferences: mapNotificationPreferencesRow(row),
  };
}

export async function updateNotificationPreferences(
  userId: string,
  input: UpdateNotificationPreferencesInput,
): Promise<NotificationPreferencesResult> {
  const pool = getPostgresPool();
  const timingPresets = normalizeTimingPresets(input.timingPresets);
  const result = await pool.query<NotificationPreferencesRow>(
    `
      insert into notification_preferences (
        user_id,
        in_app_enabled,
        push_enabled,
        release_date_changed_enabled,
        release_approaching_enabled,
        timing_presets,
        updated_at
      ) values (
        $1::uuid,
        $2::boolean,
        $3::boolean,
        $4::boolean,
        $5::boolean,
        $6::text[],
        timezone('utc', now())
      )
      on conflict (user_id) do update set
        in_app_enabled = excluded.in_app_enabled,
        push_enabled = excluded.push_enabled,
        release_date_changed_enabled = excluded.release_date_changed_enabled,
        release_approaching_enabled = excluded.release_approaching_enabled,
        timing_presets = excluded.timing_presets,
        updated_at = timezone('utc', now())
      returning
        in_app_enabled,
        push_enabled,
        release_date_changed_enabled,
        release_approaching_enabled,
        timing_presets,
        updated_at
    `,
    [
      userId,
      input.channels.inApp,
      input.channels.push,
      input.events.releaseDateChanged,
      input.events.releaseApproaching,
      timingPresets,
    ],
  );

  return {
    preferences: mapNotificationPreferencesRow(result.rows[0]!),
  };
}

function mapNotificationRecord(row: NotificationRecordRow): NotificationRecord {
  return {
    id: row.id,
    titleId: row.title_id,
    eventType: row.event_type,
    destinationKind: row.destination_kind,
    destinationTitleId: row.destination_title_id,
    titleName: row.title_name,
    titleArtworkUrl: row.title_artwork_url,
    message: row.message,
    subtitle: row.subtitle,
    payload: normalizeNotificationPayload(row.event_type, row.payload),
    createdAt: row.created_at,
    readAt: row.read_at,
  };
}

/**
 * Forces a stored payload into the shape the response schema declares.
 *
 * Responses are validated on the way out, so a single row carrying a payload
 * the schema rejects failed serialization and took the whole list with it —
 * not just that row, and not just once: it stayed broken until the data was
 * fixed by hand. A column typed `jsonb` cannot promise otherwise, so nothing
 * reaches a response without passing through here.
 *
 * Missing parts become null rather than being invented, and an unreadable
 * timing preset is dropped: clients read the dates, and a wrong preset would
 * be worse than an absent one.
 */
export function normalizeNotificationPayload(
  eventType: NotificationRecord["eventType"],
  payload: unknown,
): NotificationPayload {
  const stored = isPlainObject(payload) ? payload : {};

  if (eventType === "release_approaching") {
    const timingPreset = stored.timingPreset;

    return {
      targetReleaseDate: nullableString(stored.targetReleaseDate),
      ...(isTimingPreset(timingPreset) ? { timingPreset } : {}),
    } as NotificationPayload;
  }

  return {
    previousReleaseDate: nullableString(stored.previousReleaseDate),
    nextReleaseDate: nullableString(stored.nextReleaseDate),
  };
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === "object" && value !== null && Array.isArray(value) === false
  );
}

function nullableString(value: unknown) {
  return typeof value === "string" ? value : null;
}

function isTimingPreset(value: unknown): value is NotificationTimingPreset {
  return (
    typeof value === "string" &&
    (notificationTimingPresetValues as readonly string[]).includes(value)
  );
}

function mapNotificationPreferencesRow(
  row: NotificationPreferencesRow,
): NotificationPreferences {
  return {
    channels: {
      inApp: row.in_app_enabled,
      push: row.push_enabled,
    },
    events: {
      releaseDateChanged: row.release_date_changed_enabled,
      releaseApproaching: row.release_approaching_enabled,
    },
    timingPresets: normalizeTimingPresets(row.timing_presets),
    updatedAt: row.updated_at,
  };
}

function normalizeTimingPresets(values: string[]): NotificationTimingPreset[] {
  const unique = new Set<NotificationTimingPreset>();
  for (const value of values) {
    if (isNotificationTimingPreset(value)) {
      unique.add(value);
    }
  }

  if (unique.size === 0) {
    return ["on_day"];
  }

  return Array.from(unique);
}

function isNotificationTimingPreset(
  value: string,
): value is NotificationTimingPreset {
  return (VALID_TIMING_PRESETS as string[]).includes(value);
}

function normalizeLimit(limit: number | undefined) {
  if (!Number.isInteger(limit) || !limit) {
    return DEFAULT_PAGE_LIMIT;
  }

  return Math.min(Math.max(limit, 1), MAX_PAGE_LIMIT);
}

export async function markAllAsRead(
  userId: string,
): Promise<MarkAllNotificationsReadResult> {
  const pool = getPostgresPool();
  const result = await pool.query(
    `
      update notification_records
      set read_at = timezone('utc', now())
      where user_id = $1::uuid
        and read_at is null
    `,
    [userId],
  );

  return { markedCount: result.rowCount ?? 0 };
}

export async function markAsRead(
  userId: string,
  notificationId: string,
): Promise<MarkNotificationReadResult | null> {
  const normalizedNotificationId = notificationId.trim();

  if (!normalizedNotificationId) {
    return null;
  }

  const pool = getPostgresPool();
  const result = await pool.query<NotificationRecordRow>(
    `
      with existing as (
        select
          id,
          title_id,
          event_type,
          destination_kind,
          destination_title_id,
          title_name,
          title_artwork_url,
          message,
          subtitle,
          payload,
          created_at,
          read_at
        from notification_records
        where user_id = $1::uuid
          and id = $2::text
      ),
      updated as (
        update notification_records
        set read_at = timezone('utc', now())
        where user_id = $1::uuid
          and id = $2::text
          and read_at is null
        returning
          id,
          title_id,
          event_type,
          destination_kind,
          destination_title_id,
          title_name,
          title_artwork_url,
          message,
          subtitle,
          payload,
          created_at,
          read_at
      )
      select * from updated
      union all
      select * from existing
      where not exists (select 1 from updated)
      limit 1
    `,
    [userId, normalizedNotificationId],
  );

  const row = result.rows[0];
  if (!row) {
    return null;
  }

  return {
    notification: mapNotificationRecord(row),
  };
}

function encodeCursor(createdAt: string, id: string) {
  return Buffer.from(JSON.stringify({ createdAt, id }), "utf8").toString(
    "base64url",
  );
}

function decodeCursor(cursor: string) {
  try {
    const parsed = JSON.parse(
      Buffer.from(cursor, "base64url").toString("utf8"),
    ) as { createdAt?: unknown; id?: unknown };

    if (
      typeof parsed.createdAt === "string" &&
      parsed.createdAt.length > 0 &&
      typeof parsed.id === "string" &&
      parsed.id.length > 0
    ) {
      return { createdAt: parsed.createdAt, id: parsed.id };
    }
  } catch {
    return null;
  }

  return null;
}
