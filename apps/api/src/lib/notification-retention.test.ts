import assert from "node:assert/strict";
import test from "node:test";

import {
  DEFAULT_RETENTION_DAYS,
  type NotificationRetentionStore,
  normalizeRetentionDays,
  pruneNotifications,
} from "./notification-retention";

function recordingStore(deletedRecords = 0, deletedEvents = 0) {
  const calls: { olderThanDays: number }[] = [];
  let orphanSweeps = 0;

  const store: NotificationRetentionStore = {
    deleteReadNotificationsBefore: async (params) => {
      calls.push(params);
      return deletedRecords;
    },
    deleteOrphanedEvents: async () => {
      orphanSweeps += 1;
      return deletedEvents;
    },
  };

  return { store, calls, sweeps: () => orphanSweeps };
}

test("prunes read notifications past the retention window", async () => {
  const { store, calls } = recordingStore(12);

  const summary = await pruneNotifications({ store }, { olderThanDays: 90 });

  assert.deepEqual(calls, [{ olderThanDays: 90 }]);
  assert.equal(summary.deletedRecords, 12);
  assert.equal(summary.olderThanDays, 90);
});

test("falls back to the default window", async () => {
  const { store, calls } = recordingStore();

  await pruneNotifications({ store });

  assert.deepEqual(calls, [{ olderThanDays: DEFAULT_RETENTION_DAYS }]);
});

// Events are shared between everyone watching the same game, so one user's
// tidying must not take another's notification with it.
test("sweeps events only once records have actually gone", async () => {
  const { store, sweeps } = recordingStore(0, 5);

  const summary = await pruneNotifications({ store });

  assert.equal(sweeps(), 0);
  assert.equal(summary.deletedEvents, 0);
});

test("sweeps orphaned events after deleting records", async () => {
  const { store, sweeps } = recordingStore(3, 2);

  const summary = await pruneNotifications({ store });

  assert.equal(sweeps(), 1);
  assert.equal(summary.deletedEvents, 2);
});

// A window of zero would delete everything already read — a plausible typo and
// an unrecoverable one.
test("a retention window is never less than a day", () => {
  assert.equal(normalizeRetentionDays(0), 1);
  assert.equal(normalizeRetentionDays(-30), 1);
});

test("a missing or unreadable window falls back to the default", () => {
  assert.equal(normalizeRetentionDays(undefined), DEFAULT_RETENTION_DAYS);
  assert.equal(normalizeRetentionDays(Number.NaN), DEFAULT_RETENTION_DAYS);
});

test("a fractional window is floored rather than rejected", () => {
  assert.equal(normalizeRetentionDays(30.9), 30);
});
