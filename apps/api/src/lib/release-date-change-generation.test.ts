import assert from "node:assert/strict";
import test from "node:test";

import {
  type PendingReleaseDateChange,
  type ReleaseDateChangeStore,
  eventKey,
  generateReleaseDateChangeNotifications,
} from "./release-date-change-generation";

function recordingStore(pending: PendingReleaseDateChange[], watchers = 3) {
  const notified: { titleId: string; previous: string; next: string }[] = [];
  const processed: number[] = [];

  const store: ReleaseDateChangeStore = {
    pendingChanges: async () => pending,
    notifyWatchers: async ({
      titleId,
      previousReleaseDate,
      nextReleaseDate,
    }) => {
      notified.push({
        titleId,
        previous: previousReleaseDate,
        next: nextReleaseDate,
      });
      return watchers;
    },
    markProcessed: async (ids) => {
      processed.push(...ids);
    },
  };

  return { store, notified, processed };
}

function change(
  overrides: Partial<PendingReleaseDateChange> = {},
): PendingReleaseDateChange {
  return {
    titleId: "rawg:1",
    previousReleaseDate: "2026-04-17",
    nextReleaseDate: "2026-11-19",
    changeIds: [1],
    ...overrides,
  };
}

test("a moved date is told to watchers", async () => {
  const { store, notified } = recordingStore([change()]);

  const summary = await generateReleaseDateChangeNotifications({ store });

  assert.deepEqual(notified, [
    { titleId: "rawg:1", previous: "2026-04-17", next: "2026-11-19" },
  ]);
  assert.equal(summary.titlesNotified, 1);
  assert.equal(summary.insertedRecordCount, 3);
});

// A provider that moves a date and moves it back leaves two rows saying so,
// and the reader cares about neither: the date they were told is the date it
// still is.
test("a date that moved and moved back is not news", async () => {
  const { store, notified } = recordingStore([
    change({
      previousReleaseDate: "2026-04-17",
      nextReleaseDate: "2026-04-17",
      changeIds: [1, 2],
    }),
  ]);

  const summary = await generateReleaseDateChangeNotifications({ store });

  assert.deepEqual(notified, []);
  assert.equal(summary.titlesNotified, 0);
  assert.equal(summary.titlesConsidered, 1);
});

// Collapsing is what removes the need for a threshold on how far a date has to
// move: a day's slip is real news, a wobble is none, and the net tells them
// apart without guessing a number.
test("several moves become one piece of news", async () => {
  const { store, notified } = recordingStore([
    change({
      previousReleaseDate: "2026-04-17",
      nextReleaseDate: "2027-01-05",
      changeIds: [1, 2, 3],
    }),
  ]);

  await generateReleaseDateChangeNotifications({ store });

  assert.equal(notified.length, 1);
  assert.equal(notified[0]?.next, "2027-01-05");
});

// "Announced" and "no longer dated" are different sentences from "moved", and
// a notification that says the wrong one is worse than one that never arrives.
test("a date appearing is not treated as a move", async () => {
  const { store, notified } = recordingStore([
    change({ previousReleaseDate: null }),
  ]);

  await generateReleaseDateChangeNotifications({ store });

  assert.deepEqual(notified, []);
});

test("a date disappearing is not treated as a move", async () => {
  const { store, notified } = recordingStore([
    change({ nextReleaseDate: null }),
  ]);

  await generateReleaseDateChangeNotifications({ store });

  assert.deepEqual(notified, []);
});

// Leaving them would mean deciding about them again on every run, forever.
test("changes are processed whether or not anyone was told", async () => {
  const { store, processed } = recordingStore([
    change({ changeIds: [1, 2] }),
    change({
      titleId: "rawg:2",
      previousReleaseDate: null,
      changeIds: [3],
    }),
  ]);

  await generateReleaseDateChangeNotifications({ store });

  assert.deepEqual(processed, [1, 2, 3]);
});

test("nothing pending is not an error", async () => {
  const { store } = recordingStore([]);

  const summary = await generateReleaseDateChangeNotifications({ store });

  assert.deepEqual(summary, {
    titlesConsidered: 0,
    titlesNotified: 0,
    insertedRecordCount: 0,
  });
});

// Both dates, so a game that moves and later moves back is two pieces of news
// rather than one that cannot be told twice.
test("the event key carries where the date came from as well as where it went", () => {
  assert.equal(
    eventKey("rawg:1", "2026-04-17", "2026-11-19"),
    "release_date_changed:rawg:1:2026-04-17:2026-11-19",
  );
  assert.notEqual(
    eventKey("rawg:1", "2026-04-17", "2026-11-19"),
    eventKey("rawg:1", "2026-11-19", "2026-04-17"),
  );
});
