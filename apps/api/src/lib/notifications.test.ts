import assert from "node:assert/strict";
import test from "node:test";

import { normalizeNotificationPayload } from "./notifications";

// A payload the response schema rejects fails serialization, which fails the
// whole list rather than the row — so nothing may reach a response unnormalized.

test("a release-approaching payload keeps its date and preset", () => {
  const payload = normalizeNotificationPayload("release_approaching", {
    targetReleaseDate: "2026-01-05",
    timingPreset: "days_7_before",
  });

  assert.deepEqual(payload, {
    targetReleaseDate: "2026-01-05",
    timingPreset: "days_7_before",
  });
});

test("a missing timing preset is dropped rather than failing the row", () => {
  const payload = normalizeNotificationPayload("release_approaching", {
    targetReleaseDate: "2026-01-05",
  });

  assert.deepEqual(payload, { targetReleaseDate: "2026-01-05" });
});

test("a timing preset this build cannot read is dropped, not passed on", () => {
  const payload = normalizeNotificationPayload("release_approaching", {
    targetReleaseDate: "2026-01-05",
    timingPreset: "hours_3_before",
  });

  assert.deepEqual(payload, { targetReleaseDate: "2026-01-05" });
});

test("a missing date becomes null rather than being invented", () => {
  const payload = normalizeNotificationPayload("release_approaching", {});

  assert.deepEqual(payload, { targetReleaseDate: null });
});

test("a date stored as something other than a string becomes null", () => {
  const payload = normalizeNotificationPayload("release_approaching", {
    targetReleaseDate: 20_260_105,
  });

  assert.deepEqual(payload, { targetReleaseDate: null });
});

test("a release-date-changed payload keeps both dates", () => {
  const payload = normalizeNotificationPayload("release_date_changed", {
    previousReleaseDate: "2026-01-05",
    nextReleaseDate: "2026-03-01",
  });

  assert.deepEqual(payload, {
    previousReleaseDate: "2026-01-05",
    nextReleaseDate: "2026-03-01",
  });
});

test("a half-written release-date-changed payload is completed with nulls", () => {
  const payload = normalizeNotificationPayload("release_date_changed", {
    nextReleaseDate: "2026-03-01",
  });

  assert.deepEqual(payload, {
    previousReleaseDate: null,
    nextReleaseDate: "2026-03-01",
  });
});

test("a payload that is not an object at all still yields a valid one", () => {
  for (const stored of [null, undefined, "release_approaching", 7, []]) {
    assert.deepEqual(
      normalizeNotificationPayload("release_approaching", stored),
      { targetReleaseDate: null },
      `failed for ${JSON.stringify(stored)}`,
    );
  }
});

test("keys the schema does not declare are not passed through", () => {
  const payload = normalizeNotificationPayload("release_approaching", {
    targetReleaseDate: "2026-01-05",
    timingPreset: "on_day",
    injected: "anything at all",
  });

  assert.deepEqual(Object.keys(payload).sort(), [
    "targetReleaseDate",
    "timingPreset",
  ]);
});
