import assert from "node:assert/strict";
import { createVerify, generateKeyPairSync } from "node:crypto";
import test from "node:test";

import {
  type ApnsCredentials,
  type ApnsResponse,
  type ApnsTransport,
  ApnsSender,
  apnsPayload,
  classifyApnsResponse,
  createApnsAuthToken,
} from "./apns";

const { privateKey, publicKey } = generateKeyPairSync("ec", {
  namedCurve: "P-256",
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
  publicKeyEncoding: { type: "spki", format: "pem" },
});

const credentials: ApnsCredentials = {
  keyId: "ABC123DEFG",
  teamId: "TEAM123456",
  bundleId: "com.ashtar23.soonr.native",
  privateKey,
};

const notification = {
  token: "a".repeat(64),
  environment: "sandbox" as const,
  title: "Marvel's Wolverine",
  body: "Out today",
  destinationTitleId: "rawg:662318",
  notificationId: "notification-1",
};

function decodeSegment(segment: string) {
  return JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
}

function stubTransport(response: ApnsResponse) {
  const sent: Parameters<ApnsTransport["post"]>[0][] = [];
  const transport: ApnsTransport = {
    post: async (params) => {
      sent.push(params);
      return response;
    },
  };

  return { transport, sent };
}

test("the provider token names the key and the team Apple expects", () => {
  const [header = "", claims = ""] = createApnsAuthToken(
    credentials,
    1_700_000_000,
  ).split(".");

  assert.deepEqual(decodeSegment(header), { alg: "ES256", kid: "ABC123DEFG" });
  assert.deepEqual(decodeSegment(claims), {
    iss: "TEAM123456",
    iat: 1_700_000_000,
  });
});

// Node signs EC keys as DER unless told otherwise; a JWT needs the raw r||s
// pair. Verifying with the same encoding is what catches the difference.
test("the provider token is signed so Apple can verify it", () => {
  const token = createApnsAuthToken(credentials, 1_700_000_000);
  const [header = "", claims = "", signature = ""] = token.split(".");

  const verified = createVerify("SHA256")
    .update(`${header}.${claims}`)
    .verify(
      { key: publicKey, dsaEncoding: "ieee-p1363" },
      Buffer.from(signature, "base64url"),
    );

  assert.equal(verified, true);
  assert.equal(Buffer.from(signature, "base64url").length, 64);
});

test("the payload carries the alert and what the tap should open", () => {
  const payload = JSON.parse(apnsPayload(notification));

  assert.deepEqual(payload.aps.alert, {
    title: "Marvel's Wolverine",
    body: "Out today",
  });
  assert.equal(payload.destinationTitleId, "rawg:662318");
  assert.equal(payload.notificationId, "notification-1");
  assert.equal("badge" in payload.aps, false);
});

test("a badge is sent only when there is one to send", () => {
  const payload = JSON.parse(apnsPayload({ ...notification, badge: 3 }));

  assert.equal(payload.aps.badge, 3);
});

test("a sandbox notification goes to the sandbox host", async () => {
  const { transport, sent } = stubTransport({ statusCode: 200, body: "" });

  await new ApnsSender(credentials, transport).send(notification);

  assert.equal(sent[0]?.host, "api.sandbox.push.apple.com");
  assert.equal(sent[0]?.path, `/3/device/${notification.token}`);
  assert.equal(sent[0]?.headers["apns-topic"], "com.ashtar23.soonr.native");
  assert.equal(sent[0]?.headers["apns-push-type"], "alert");
});

test("a production notification goes to the production host", async () => {
  const { transport, sent } = stubTransport({ statusCode: 200, body: "" });

  await new ApnsSender(credentials, transport).send({
    ...notification,
    environment: "production",
  });

  assert.equal(sent[0]?.host, "api.push.apple.com");
});

// Apple rejects a provider token minted per notification as abuse, and one
// older than an hour as expired.
test("one provider token is reused across a run", async () => {
  const { transport, sent } = stubTransport({ statusCode: 200, body: "" });
  const sender = new ApnsSender(credentials, transport, () => 1_700_000_000);

  await sender.send(notification);
  await sender.send(notification);

  assert.equal(sent[0]?.headers.authorization, sent[1]?.headers.authorization);
});

test("the provider token is renewed before Apple would refuse it", async () => {
  const { transport, sent } = stubTransport({ statusCode: 200, body: "" });
  let now = 1_700_000_000;
  const sender = new ApnsSender(credentials, transport, () => now);

  await sender.send(notification);
  now += 50 * 60;
  await sender.send(notification);

  assert.notEqual(
    sent[0]?.headers.authorization,
    sent[1]?.headers.authorization,
  );
});

test("a 200 is a delivered notification", () => {
  assert.deepEqual(classifyApnsResponse({ statusCode: 200, body: "" }), {
    status: "sent",
  });
});

test("a 410 means the device is gone", () => {
  assert.deepEqual(
    classifyApnsResponse({
      statusCode: 410,
      body: '{"reason":"Unregistered"}',
    }),
    { status: "unregistered" },
  );
});

// What a sandbox token sent to production looks like, and the reason the
// environment is stored per token.
test("a token rejected as bad means the device is gone", () => {
  assert.deepEqual(
    classifyApnsResponse({
      statusCode: 400,
      body: '{"reason":"BadDeviceToken"}',
    }),
    { status: "unregistered" },
  );
});

test("Apple asking for it later is retryable", () => {
  const result = classifyApnsResponse({
    statusCode: 503,
    body: '{"reason":"ServiceUnavailable"}',
  });

  assert.deepEqual(result, {
    status: "failed",
    reason: "ServiceUnavailable",
    retryable: true,
  });
});

test("a payload Apple will never accept is not retryable", () => {
  const result = classifyApnsResponse({
    statusCode: 400,
    body: '{"reason":"PayloadTooLarge"}',
  });

  assert.equal(result.status, "failed");
  assert.equal(result.status === "failed" && result.retryable, false);
});

test("a response that is not JSON still reports something usable", () => {
  const result = classifyApnsResponse({
    statusCode: 502,
    body: "<html>bad gateway</html>",
  });

  assert.equal(result.status, "failed");
  assert.match(result.status === "failed" ? result.reason : "", /bad gateway/);
});
