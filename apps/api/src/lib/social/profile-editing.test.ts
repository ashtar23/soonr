import assert from "node:assert/strict";
import test from "node:test";

import {
  type EditedProfile,
  MAXIMUM_BIO_LENGTH,
  MAXIMUM_DISPLAY_NAME_LENGTH,
  type ProfileEdit,
  ProfileEditError,
  type ProfileEditStore,
  editProfile,
} from "./profile-editing";

const userId = "e0a59a82-83eb-4189-9212-7dbf96ff099f";

function profile(overrides: Partial<EditedProfile> = {}): EditedProfile {
  return {
    userId,
    username: "reader",
    displayName: "A Reader",
    avatarUrl: null,
    bio: null,
    watchlistVisibility: "friends",
    ...overrides,
  };
}

function recordingStore(
  result: EditedProfile | null = profile(),
  failWith?: unknown,
) {
  const calls: Record<string, unknown>[] = [];

  const store: ProfileEditStore = {
    updateProfile: async (params) => {
      calls.push(params);

      if (failWith) {
        throw failWith;
      }

      return result;
    },
  };

  return { store, calls };
}

async function edit(store: ProfileEditStore, patch: ProfileEdit) {
  return editProfile({ store }, { userId, edit: patch });
}

test("sets a username, normalized", async () => {
  const { store, calls } = recordingStore();

  await edit(store, { username: "  ReaderOne  " });

  assert.equal(calls[0]?.username, "readerone");
});

// A field left out is left alone, which is what makes this safe to call from a
// form that edits one thing.
test("a field not mentioned is not sent", async () => {
  const { store, calls } = recordingStore();

  await edit(store, { bio: "Plays too much" });

  assert.equal("username" in (calls[0] ?? {}), false);
  assert.equal("displayName" in (calls[0] ?? {}), false);
  assert.equal(calls[0]?.bio, "Plays too much");
});

// The difference between "not mentioned" and "cleared" is the whole reason
// this takes a patch rather than a whole profile.
test("null clears a field", async () => {
  const { store, calls } = recordingStore();

  await edit(store, { bio: null, displayName: null });

  assert.equal(calls[0]?.bio, null);
  assert.equal(calls[0]?.displayName, null);
});

// Whitespace is not a display name, and storing it makes every screen cope.
test("a field of whitespace clears rather than storing spaces", async () => {
  const { store, calls } = recordingStore();

  await edit(store, { displayName: "   ", bio: "\n\t " });

  assert.equal(calls[0]?.displayName, null);
  assert.equal(calls[0]?.bio, null);
});

test("an invalid username is refused before the database sees it", async () => {
  const { store, calls } = recordingStore();

  await assert.rejects(
    () => edit(store, { username: "no spaces" }),
    (error: ProfileEditError) => error.reason === "invalid_username",
  );
  assert.equal(calls.length, 0);
});

test("a reserved username is refused", async () => {
  const { store } = recordingStore();

  await assert.rejects(
    () => edit(store, { username: "admin" }),
    (error: ProfileEditError) => error.reason === "reserved_username",
  );
});

// Two people can pass an availability check at the same moment and only one
// can have the name, so the database stays the authority.
test("a username taken between checking and saving is a conflict", async () => {
  const { store } = recordingStore(profile(), {
    constraint: "user_profiles_username_normalized_key",
  });

  await assert.rejects(
    () => edit(store, { username: "reader" }),
    (error: ProfileEditError) => error.reason === "username_taken",
  );
});

test("an unrelated database failure is not reported as a taken name", async () => {
  const { store } = recordingStore(profile(), new Error("connection lost"));

  await assert.rejects(
    () => edit(store, { username: "reader" }),
    (error: Error) => error.message === "connection lost",
  );
});

test("an account with no profile row has nothing to edit", async () => {
  const { store } = recordingStore(null);

  await assert.rejects(
    () => edit(store, { bio: "hello" }),
    (error: ProfileEditError) => error.reason === "no_profile",
  );
});

test("a bio longer than the limit is refused", async () => {
  const { store } = recordingStore();

  await assert.rejects(
    () => edit(store, { bio: "x".repeat(MAXIMUM_BIO_LENGTH + 1) }),
    (error: ProfileEditError) => error.reason === "bio_too_long",
  );
});

test("a bio exactly at the limit is allowed", async () => {
  const { store, calls } = recordingStore();

  await edit(store, { bio: "x".repeat(MAXIMUM_BIO_LENGTH) });

  assert.equal(String(calls[0]?.bio).length, MAXIMUM_BIO_LENGTH);
});

test("a display name longer than the limit is refused", async () => {
  const { store } = recordingStore();

  await assert.rejects(
    () =>
      edit(store, {
        displayName: "x".repeat(MAXIMUM_DISPLAY_NAME_LENGTH + 1),
      }),
    (error: ProfileEditError) => error.reason === "display_name_too_long",
  );
});

test("visibility is passed through", async () => {
  const { store, calls } = recordingStore();

  await edit(store, { watchlistVisibility: "private" });

  assert.equal(calls[0]?.watchlistVisibility, "private");
});

test("the saved profile is returned", async () => {
  const { store } = recordingStore(profile({ username: "readerone" }));

  const updated = await edit(store, { username: "readerone" });

  assert.equal(updated.username, "readerone");
});
