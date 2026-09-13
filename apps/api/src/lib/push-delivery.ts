import type { ApnsNotification, ApnsResult } from "./apns";
import { getPostgresPool } from "./postgres";
import type { DeviceEnvironment } from "./push-devices";

export interface PendingPushDevice {
  token: string;
  environment: DeviceEnvironment;
}

export interface PendingPushNotification {
  notificationId: string;
  userId: string;
  title: string;
  body: string;
  destinationTitleId: string;
  unreadCount: number;
  devices: PendingPushDevice[];
}

export interface PushDeliveryStore {
  listPending: (limit: number) => Promise<PendingPushNotification[]>;
  markPushed: (notificationId: string) => Promise<void>;
  deleteDeviceToken: (token: string) => Promise<void>;
}

export interface PushSender {
  send: (notification: ApnsNotification) => Promise<ApnsResult>;
}

export interface PushDeliverySummary {
  considered: number;
  sent: number;
  unregisteredTokensRemoved: number;
  failed: number;
  deferred: number;
}

export interface DeliverPushNotificationsOptions {
  limit?: number;
}

/**
 * Hands unsent notifications to APNs, once each.
 *
 * A notification is settled — marked as pushed — as soon as one device takes
 * it, or when every device refused it for a reason that will not change.
 * Only a refusal Apple asks us to repeat leaves it unsettled, so the next run
 * tries again rather than dropping it.
 */
export async function deliverPushNotifications(
  deps: { store: PushDeliveryStore; sender: PushSender },
  options: DeliverPushNotificationsOptions = {},
): Promise<PushDeliverySummary> {
  const pending = await deps.store.listPending(options.limit ?? 200);

  const summary: PushDeliverySummary = {
    considered: pending.length,
    sent: 0,
    unregisteredTokensRemoved: 0,
    failed: 0,
    deferred: 0,
  };

  for (const notification of pending) {
    let delivered = false;
    let worthRetrying = false;

    for (const device of notification.devices) {
      const result = await deps.sender.send({
        token: device.token,
        environment: device.environment,
        title: notification.title,
        body: notification.body,
        destinationTitleId: notification.destinationTitleId,
        notificationId: notification.notificationId,
        badge: notification.unreadCount,
      });

      if (result.status === "sent") {
        delivered = true;
        summary.sent += 1;
        continue;
      }

      if (result.status === "unregistered") {
        await deps.store.deleteDeviceToken(device.token);
        summary.unregisteredTokensRemoved += 1;
        continue;
      }

      summary.failed += 1;
      worthRetrying ||= result.retryable;
    }

    if (delivered || !worthRetrying) {
      await deps.store.markPushed(notification.notificationId);
    } else {
      summary.deferred += 1;
    }
  }

  return summary;
}

/**
 * Only records from the last day, and only for accounts with a device
 * already registered. Without both, registering a device would deliver every
 * notification the account had ever accumulated.
 */
const pendingWindow = "1 day";

export const postgresPushDeliveryStore: PushDeliveryStore = {
  async listPending(limit) {
    const pool = getPostgresPool();
    const result = await pool.query<{
      notification_id: string;
      user_id: string;
      title: string;
      body: string;
      destination_title_id: string;
      unread_count: number;
      devices: PendingPushDevice[];
    }>(
      `
        with pending as (
          select
            r.id,
            r.user_id,
            r.title_name,
            coalesce(r.subtitle, r.message) as body,
            r.destination_title_id,
            r.created_at
          from public.notification_records r
          left join public.notification_preferences np
            on np.user_id = r.user_id
          where r.pushed_at is null
            and r.read_at is null
            and r.created_at > timezone('utc', now()) - interval '${pendingWindow}'
            -- Push is off until an account turns it on, which is what the
            -- column defaults to for an account that never saved preferences.
            and coalesce(np.push_enabled, false)
            and case r.event_type
              when 'release_approaching' then
                coalesce(np.release_approaching_enabled, true)
              when 'release_date_changed' then
                coalesce(np.release_date_changed_enabled, true)
              else true
            end
          order by r.created_at asc
          limit $1
        )
        select
          p.id as notification_id,
          p.user_id,
          p.title_name as title,
          p.body,
          p.destination_title_id,
          (
            select count(*)
            from public.notification_records unread
            where unread.user_id = p.user_id
              and unread.read_at is null
          )::int as unread_count,
          json_agg(
            json_build_object('token', d.token, 'environment', d.environment)
          ) as devices
        from pending p
        join public.device_tokens d on d.user_id = p.user_id
        group by
          p.id,
          p.user_id,
          p.title_name,
          p.body,
          p.destination_title_id,
          p.created_at
        order by p.created_at asc
      `,
      [limit],
    );

    return result.rows.map((row) => ({
      notificationId: row.notification_id,
      userId: row.user_id,
      title: row.title,
      body: row.body,
      destinationTitleId: row.destination_title_id,
      unreadCount: row.unread_count,
      devices: row.devices,
    }));
  },

  async markPushed(notificationId) {
    const pool = getPostgresPool();
    await pool.query(
      `
        update public.notification_records
        set pushed_at = timezone('utc', now())
        where id = $1::text
      `,
      [notificationId],
    );
  },

  async deleteDeviceToken(token) {
    const pool = getPostgresPool();
    await pool.query(
      `
        delete from public.device_tokens
        where token = $1::text
      `,
      [token],
    );
  },
};
