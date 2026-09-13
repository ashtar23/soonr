import { getPostgresPool } from "./postgres";

export const devicePlatforms = ["ios"] as const;
export const deviceEnvironments = ["sandbox", "production"] as const;

export type DevicePlatform = (typeof devicePlatforms)[number];
export type DeviceEnvironment = (typeof deviceEnvironments)[number];

export interface DeviceRegistrationInput {
  token: string;
  platform: DevicePlatform;
  environment: DeviceEnvironment;
}

export interface DeviceToken {
  token: string;
  platform: DevicePlatform;
  environment: DeviceEnvironment;
}

export interface DeviceTokenStore {
  upsertDeviceToken: (params: {
    userId: string;
    token: string;
    platform: DevicePlatform;
    environment: DeviceEnvironment;
  }) => Promise<void>;
  deleteDeviceToken: (params: {
    userId: string;
    token: string;
  }) => Promise<boolean>;
}

export class DeviceTokenValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DeviceTokenValidationError";
  }
}

/**
 * APNs tokens are hexadecimal and case-insensitive, so the same device can
 * present the same token in two spellings. Normalizing keeps that from
 * becoming two rows, and two copies of every notification.
 */
export function normalizeDeviceToken(token: string) {
  const normalized = token.trim().toLowerCase();

  if (!/^[0-9a-f]+$/.test(normalized)) {
    throw new DeviceTokenValidationError("Device token must be hexadecimal.");
  }

  // Today's tokens are 32 bytes. The bounds are wide because a token that
  // grows is Apple's to decide and a rejected one cannot be notified.
  if (normalized.length < 64 || normalized.length > 256) {
    throw new DeviceTokenValidationError("Device token length is invalid.");
  }

  return normalized;
}

export async function registerDeviceToken(
  params: { userId: string } & DeviceRegistrationInput,
  store: DeviceTokenStore = postgresDeviceTokenStore,
): Promise<DeviceToken> {
  const token = normalizeDeviceToken(params.token);

  await store.upsertDeviceToken({
    userId: params.userId,
    token,
    platform: params.platform,
    environment: params.environment,
  });

  return {
    token,
    platform: params.platform,
    environment: params.environment,
  };
}

export async function unregisterDeviceToken(
  params: { userId: string; token: string },
  store: DeviceTokenStore = postgresDeviceTokenStore,
) {
  const token = normalizeDeviceToken(params.token);

  return store.deleteDeviceToken({ userId: params.userId, token });
}

export const postgresDeviceTokenStore: DeviceTokenStore = {
  async upsertDeviceToken({ userId, token, platform, environment }) {
    const pool = getPostgresPool();
    await pool.query(
      `
        insert into public.device_tokens (
          token,
          user_id,
          platform,
          environment
        )
        values ($1::text, $2::uuid, $3::text, $4::text)
        on conflict (token) do update
        set
          user_id = excluded.user_id,
          platform = excluded.platform,
          environment = excluded.environment,
          updated_at = timezone('utc', now())
      `,
      [token, userId, platform, environment],
    );
  },

  async deleteDeviceToken({ userId, token }) {
    const pool = getPostgresPool();
    // Scoped to the owner, so signing out cannot remove a token that has since
    // been claimed by whoever signed in after.
    const result = await pool.query(
      `
        delete from public.device_tokens
        where token = $1::text
          and user_id = $2::uuid
      `,
      [token, userId],
    );

    return (result.rowCount ?? 0) > 0;
  },
};
