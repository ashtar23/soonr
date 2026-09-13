import assert from "node:assert/strict";
import test from "node:test";

import {
  AuthApiError,
  AuthRetryableFetchError,
  type UserResponse,
} from "@supabase/supabase-js";

import {
  authenticateAccessToken,
  fetchAuthUserById,
  isAuthServiceUnavailable,
} from "./auth";

const user = { id: "user-1", email: "viewer@example.com" };

function rejected(error: AuthApiError | AuthRetryableFetchError) {
  return { data: { user: null }, error } as unknown as UserResponse;
}

function accepted() {
  return { data: { user }, error: null } as unknown as UserResponse;
}

test("an invalid token is not the auth service being unavailable", () => {
  const error = new AuthApiError(
    "invalid claim: missing sub claim",
    401,
    "bad_jwt",
  );

  assert.equal(isAuthServiceUnavailable(error), false);
});

test("a network failure reaching the auth service is unavailability", () => {
  const error = new AuthRetryableFetchError("Failed to fetch", 0);

  assert.equal(isAuthServiceUnavailable(error), true);
});

test("a 500 from the auth service is unavailability", () => {
  const error = new AuthApiError("Internal Server Error", 500, undefined);

  assert.equal(isAuthServiceUnavailable(error), true);
});

test("authenticateAccessToken returns the user a valid token belongs to", async () => {
  const verified = await authenticateAccessToken("good-token", {
    getUser: async () => accepted(),
  });

  assert.equal(verified?.id, "user-1");
});

test("authenticateAccessToken rejects a token the service says is invalid", async () => {
  const verified = await authenticateAccessToken("bad-token", {
    getUser: async () =>
      rejected(new AuthApiError("invalid claim", 401, "bad_jwt")),
  });

  assert.equal(verified, null);
});

// Returning null here would have the route answer 401, which the app reads as
// "sign in again" — for an outage that says nothing about the caller's token.
test("authenticateAccessToken throws when the auth service cannot be reached", async () => {
  await assert.rejects(
    authenticateAccessToken("good-token", {
      getUser: async () =>
        rejected(new AuthRetryableFetchError("Failed to fetch", 0)),
    }),
    AuthRetryableFetchError,
  );
});

test("fetchAuthUserById reports a genuinely missing user as missing", async () => {
  const found = await fetchAuthUserById("user-404", {
    getUserById: async () =>
      rejected(new AuthApiError("User not found", 404, "user_not_found")),
  });

  assert.equal(found, null);
});

// A missing user and an unreachable service are different answers: the first
// is a 404, the second must not be.
test("fetchAuthUserById throws when the auth service cannot be reached", async () => {
  await assert.rejects(
    fetchAuthUserById("user-1", {
      getUserById: async () =>
        rejected(new AuthRetryableFetchError("Failed to fetch", 0)),
    }),
    AuthRetryableFetchError,
  );
});
