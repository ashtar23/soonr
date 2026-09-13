import assert from "node:assert/strict";
import test from "node:test";

import {
  DeviceTokenValidationError,
  type DeviceTokenStore,
  registerDeviceToken,
  unregisterDeviceToken,
} from "./push-devices";

const token = "A".repeat(64);

function recordingStore(deleted = true) {
  const upserts: unknown[] = [];
  const deletes: unknown[] = [];

  const store: DeviceTokenStore = {
    upsertDeviceToken: async (params) => {
      upserts.push(params);
    },
    deleteDeviceToken: async (params) => {
      deletes.push(params);
      return deleted;
    },
  };

  return { store, upserts, deletes };
}

// The same device can present its token in either case. Two rows would mean
// two copies of every notification.
test("a token is stored in one casing however it arrives", async () => {
  const { store, upserts } = recordingStore();

  await registerDeviceToken(
    { userId: "user-1", token, platform: "ios", environment: "sandbox" },
    store,
  );

  assert.deepEqual(upserts, [
    {
      userId: "user-1",
      token: token.toLowerCase(),
      platform: "ios",
      environment: "sandbox",
    },
  ]);
});

test("surrounding whitespace does not become part of the token", async () => {
  const { store, upserts } = recordingStore();

  await registerDeviceToken(
    {
      userId: "user-1",
      token: `  ${token}\n`,
      platform: "ios",
      environment: "production",
    },
    store,
  );

  assert.equal((upserts[0] as { token: string }).token, token.toLowerCase());
});

test("registering reports back what was stored", async () => {
  const { store } = recordingStore();

  const device = await registerDeviceToken(
    { userId: "user-1", token, platform: "ios", environment: "sandbox" },
    store,
  );

  assert.deepEqual(device, {
    token: token.toLowerCase(),
    platform: "ios",
    environment: "sandbox",
  });
});

test("a token that is not hexadecimal is rejected", async () => {
  const { store, upserts } = recordingStore();

  await assert.rejects(
    registerDeviceToken(
      {
        userId: "user-1",
        token: `${"a".repeat(63)}z`,
        platform: "ios",
        environment: "sandbox",
      },
      store,
    ),
    DeviceTokenValidationError,
  );

  assert.equal(upserts.length, 0);
});

test("a token that is too short to be one is rejected", async () => {
  const { store } = recordingStore();

  await assert.rejects(
    registerDeviceToken(
      {
        userId: "user-1",
        token: "abcdef",
        platform: "ios",
        environment: "sandbox",
      },
      store,
    ),
    DeviceTokenValidationError,
  );
});

// Scoped to the owner: a token claimed by whoever signed in next is no longer
// the previous account's to remove.
test("removing a device names both the token and its owner", async () => {
  const { store, deletes } = recordingStore();

  const removed = await unregisterDeviceToken(
    { userId: "user-1", token },
    store,
  );

  assert.equal(removed, true);
  assert.deepEqual(deletes, [{ userId: "user-1", token: token.toLowerCase() }]);
});

test("removing a device that is not registered reports that nothing went", async () => {
  const { store } = recordingStore(false);

  const removed = await unregisterDeviceToken(
    { userId: "user-1", token },
    store,
  );

  assert.equal(removed, false);
});
