import { createSign } from "node:crypto";

import type { DeviceEnvironment } from "./push-devices";

export interface ApnsCredentials {
  keyId: string;
  teamId: string;
  bundleId: string;
  /** The contents of the .p8 file Apple issues, not a path to it. */
  privateKey: string;
}

export interface ApnsNotification {
  token: string;
  environment: DeviceEnvironment;
  title: string;
  body: string;
  /** Opened when the notification is tapped. */
  destinationTitleId: string;
  /** So the app can mark the matching in-app notification read. */
  notificationId: string;
  badge?: number;
}

export type ApnsResult =
  | { status: "sent" }
  /** The device is gone, or the token was never ours. Stop sending to it. */
  | { status: "unregistered" }
  | { status: "failed"; reason: string; retryable: boolean };

export interface ApnsResponse {
  statusCode: number;
  body: string;
}

export interface ApnsTransport {
  post: (params: {
    host: string;
    path: string;
    headers: Record<string, string>;
    body: string;
  }) => Promise<ApnsResponse>;
}

const hosts: Record<DeviceEnvironment, string> = {
  sandbox: "api.sandbox.push.apple.com",
  production: "api.push.apple.com",
};

/**
 * Apple rejects a provider token older than an hour. Refreshing well inside
 * that leaves room for a slow run without minting one per notification, which
 * Apple also rejects as abuse.
 */
const authTokenLifetimeSeconds = 45 * 60;

/**
 * A token whose device is gone. Apple reports this two ways: 410 for a token
 * it has since retired, and 400 BadDeviceToken for one that was never valid
 * for this environment — which is what a sandbox token sent to production
 * looks like.
 */
const unregisteredReasons = new Set(["Unregistered", "BadDeviceToken"]);

function base64url(value: Buffer | string) {
  return Buffer.from(value)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/**
 * The provider token Apple expects: ES256 over the header and claims.
 *
 * Node signs EC keys as DER by default; JWT wants the raw r||s pair, which is
 * what `ieee-p1363` produces. A DER signature here is accepted by nothing and
 * explains nothing when it fails.
 */
export function createApnsAuthToken(
  credentials: ApnsCredentials,
  issuedAt: number = Math.floor(Date.now() / 1000),
) {
  const header = base64url(
    JSON.stringify({ alg: "ES256", kid: credentials.keyId }),
  );
  const claims = base64url(
    JSON.stringify({ iss: credentials.teamId, iat: issuedAt }),
  );
  const signingInput = `${header}.${claims}`;

  const signature = createSign("SHA256")
    .update(signingInput)
    .sign({ key: credentials.privateKey, dsaEncoding: "ieee-p1363" });

  return `${signingInput}.${base64url(signature)}`;
}

export function apnsPayload(notification: ApnsNotification) {
  return JSON.stringify({
    aps: {
      alert: {
        title: notification.title,
        body: notification.body,
      },
      sound: "default",
      ...(notification.badge === undefined
        ? {}
        : { badge: notification.badge }),
    },
    destinationTitleId: notification.destinationTitleId,
    notificationId: notification.notificationId,
  });
}

export function classifyApnsResponse(response: ApnsResponse): ApnsResult {
  if (response.statusCode === 200) {
    return { status: "sent" };
  }

  let reason = "";
  try {
    reason = (JSON.parse(response.body) as { reason?: string }).reason ?? "";
  } catch {
    reason = response.body.slice(0, 200);
  }

  if (response.statusCode === 410 || unregisteredReasons.has(reason)) {
    return { status: "unregistered" };
  }

  return {
    status: "failed",
    reason: reason || `HTTP ${response.statusCode}`,
    // 429 and 5xx are Apple asking for the same notification later; anything
    // else is about this notification and will fail again unchanged.
    retryable: response.statusCode === 429 || response.statusCode >= 500,
  };
}

/**
 * Holds one provider token for as long as Apple allows, so a run of
 * notifications signs once rather than per device.
 */
export class ApnsSender {
  private authToken: string | null = null;
  private authTokenIssuedAt = 0;

  constructor(
    private readonly credentials: ApnsCredentials,
    private readonly transport: ApnsTransport,
    private readonly now: () => number = () => Math.floor(Date.now() / 1000),
  ) {}

  async send(notification: ApnsNotification): Promise<ApnsResult> {
    const response = await this.transport.post({
      host: hosts[notification.environment],
      path: `/3/device/${notification.token}`,
      headers: {
        authorization: `bearer ${this.currentAuthToken()}`,
        "apns-topic": this.credentials.bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        // A release is still worth knowing about tomorrow, so a phone that is
        // off does not simply miss it.
        "apns-expiration": String(this.now() + 24 * 60 * 60),
        "content-type": "application/json",
      },
      body: apnsPayload(notification),
    });

    return classifyApnsResponse(response);
  }

  private currentAuthToken() {
    const now = this.now();
    if (
      this.authToken &&
      now - this.authTokenIssuedAt < authTokenLifetimeSeconds
    ) {
      return this.authToken;
    }

    this.authToken = createApnsAuthToken(this.credentials, now);
    this.authTokenIssuedAt = now;
    return this.authToken;
  }
}
