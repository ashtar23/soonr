import assert from "node:assert/strict";
import test from "node:test";

import type { ApnsNotification, ApnsResult } from "./apns";
import {
  type PendingPushNotification,
  type PushDeliveryStore,
  deliverPushNotifications,
} from "./push-delivery";

function pending(
  overrides: Partial<PendingPushNotification> = {},
): PendingPushNotification {
  return {
    notificationId: "notification-1",
    userId: "user-1",
    title: "Marvel's Wolverine",
    body: "Releases today",
    destinationTitleId: "rawg:662318",
    unreadCount: 2,
    devices: [{ token: "a".repeat(64), environment: "sandbox" }],
    ...overrides,
  };
}

function harness(
  notifications: PendingPushNotification[],
  results: ApnsResult[],
) {
  const sent: ApnsNotification[] = [];
  const pushed: string[] = [];
  const deletedTokens: string[] = [];
  let nextResult = 0;

  const store: PushDeliveryStore = {
    listPending: async () => notifications,
    markPushed: async (id) => {
      pushed.push(id);
    },
    deleteDeviceToken: async (token) => {
      deletedTokens.push(token);
    },
  };

  const sender = {
    send: async (notification: ApnsNotification) => {
      sent.push(notification);
      return results[Math.min(nextResult++, results.length - 1)] as ApnsResult;
    },
  };

  return { store, sender, sent, pushed, deletedTokens };
}

test("a notification reaches every device the account has registered", async () => {
  const { store, sender, sent } = harness(
    [
      pending({
        devices: [
          { token: "a".repeat(64), environment: "sandbox" },
          { token: "b".repeat(64), environment: "production" },
        ],
      }),
    ],
    [{ status: "sent" }],
  );

  const summary = await deliverPushNotifications({ store, sender });

  assert.equal(sent.length, 2);
  assert.equal(summary.sent, 2);
  assert.deepEqual(
    sent.map((notification) => notification.environment),
    ["sandbox", "production"],
  );
});

test("what is sent carries the alert, the destination and the badge", async () => {
  const { store, sender, sent } = harness([pending()], [{ status: "sent" }]);

  await deliverPushNotifications({ store, sender });

  assert.deepEqual(sent[0], {
    token: "a".repeat(64),
    environment: "sandbox",
    title: "Marvel's Wolverine",
    body: "Releases today",
    destinationTitleId: "rawg:662318",
    notificationId: "notification-1",
    badge: 2,
  });
});

// The guard against a repeated run, an overlapping schedule, or a manual
// invocation sending the same notification twice.
test("a delivered notification is settled so a second run does not repeat it", async () => {
  const { store, sender, pushed } = harness([pending()], [{ status: "sent" }]);

  await deliverPushNotifications({ store, sender });

  assert.deepEqual(pushed, ["notification-1"]);
});

test("a token Apple no longer knows is removed", async () => {
  const { store, sender, deletedTokens, pushed } = harness(
    [pending()],
    [{ status: "unregistered" }],
  );

  const summary = await deliverPushNotifications({ store, sender });

  assert.deepEqual(deletedTokens, ["a".repeat(64)]);
  assert.equal(summary.unregisteredTokensRemoved, 1);
  // Nothing more can be done with it, so it does not come back next run.
  assert.deepEqual(pushed, ["notification-1"]);
});

test("a failure Apple asks us to repeat is left for the next run", async () => {
  const { store, sender, pushed } = harness(
    [pending()],
    [{ status: "failed", reason: "ServiceUnavailable", retryable: true }],
  );

  const summary = await deliverPushNotifications({ store, sender });

  assert.deepEqual(pushed, []);
  assert.equal(summary.deferred, 1);
  assert.equal(summary.failed, 1);
});

test("a failure that will never succeed is not retried forever", async () => {
  const { store, sender, pushed } = harness(
    [pending()],
    [{ status: "failed", reason: "PayloadTooLarge", retryable: false }],
  );

  const summary = await deliverPushNotifications({ store, sender });

  assert.deepEqual(pushed, ["notification-1"]);
  assert.equal(summary.deferred, 0);
});

// One phone out of two being unreachable is not a reason to send the whole
// notification again.
test("one device taking it is enough to settle the notification", async () => {
  const { store, sender, pushed } = harness(
    [
      pending({
        devices: [
          { token: "a".repeat(64), environment: "sandbox" },
          { token: "b".repeat(64), environment: "sandbox" },
        ],
      }),
    ],
    [
      { status: "failed", reason: "ServiceUnavailable", retryable: true },
      { status: "sent" },
    ],
  );

  await deliverPushNotifications({ store, sender });

  assert.deepEqual(pushed, ["notification-1"]);
});

test("nothing pending sends nothing", async () => {
  const { store, sender, sent } = harness([], [{ status: "sent" }]);

  const summary = await deliverPushNotifications({ store, sender });

  assert.equal(sent.length, 0);
  assert.deepEqual(summary, {
    considered: 0,
    sent: 0,
    unregisteredTokensRemoved: 0,
    failed: 0,
    deferred: 0,
  });
});
