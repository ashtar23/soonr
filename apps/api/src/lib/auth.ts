import { isAuthRetryableFetchError } from "@supabase/supabase-js";
import type { AuthError, UserResponse } from "@supabase/supabase-js";

import { getPostgresPool } from "./postgres";
import { getSupabaseAdmin } from "./supabase";
import { normalizeAuthEmail } from "./auth-service";

export function extractAccessToken(
  authorizationHeader: string | string[] | undefined,
) {
  if (Array.isArray(authorizationHeader)) {
    return extractAccessToken(authorizationHeader[0]);
  }

  if (!authorizationHeader) {
    return null;
  }

  const match = authorizationHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    return null;
  }

  const token = match[1]?.trim();
  return token ? token : null;
}

/**
 * Tells "this token is not valid" apart from "the auth service could not be
 * asked". Only the first says anything about the caller, and answering the
 * second with a 401 signs people out over someone else's outage.
 *
 * auth-js raises a retryable fetch error for network failures and for 502, 503
 * and 504; a plain 500 arrives as an ordinary API error, so status is checked
 * as well.
 */
export function isAuthServiceUnavailable(error: AuthError) {
  return isAuthRetryableFetchError(error) || (error.status ?? 0) >= 500;
}

export interface AccessTokenVerifier {
  getUser: (accessToken: string) => Promise<UserResponse>;
}

export async function authenticateAccessToken(
  accessToken: string,
  verifier: AccessTokenVerifier = {
    getUser: (token) => getSupabaseAdmin().auth.getUser(token),
  },
) {
  const {
    data: { user },
    error,
  } = await verifier.getUser(accessToken);

  if (error) {
    if (isAuthServiceUnavailable(error)) {
      throw error;
    }

    return null;
  }

  return user ?? null;
}

export interface AuthUserLookup {
  getUserById: (userId: string) => Promise<UserResponse>;
}

export async function fetchAuthUserById(
  userId: string,
  lookup: AuthUserLookup = {
    getUserById: (id) => getSupabaseAdmin().auth.admin.getUserById(id),
  },
) {
  const {
    data: { user },
    error,
  } = await lookup.getUserById(userId);

  if (error) {
    if (isAuthServiceUnavailable(error)) {
      throw error;
    }

    return null;
  }

  return user ?? null;
}

export async function createAuthUser(params: {
  email: string;
  password: string;
  emailConfirmed: boolean;
}) {
  const {
    data: { user },
    error,
  } = await getSupabaseAdmin().auth.admin.createUser({
    email: params.email,
    password: params.password,
    email_confirm: params.emailConfirmed,
  });

  if (error || !user?.id || !user.email) {
    throw error ?? new Error("Failed to create auth user.");
  }

  return {
    userId: user.id,
    email: normalizeAuthEmail(user.email),
  };
}

export async function deleteAuthUser(userId: string) {
  const { error } = await getSupabaseAdmin().auth.admin.deleteUser(userId);
  if (error) {
    throw error;
  }
}

export async function findAuthUserByEmail(email: string) {
  const normalizedEmail = normalizeAuthEmail(email);
  let page = 1;

  while (true) {
    const { data, error } = await getSupabaseAdmin().auth.admin.listUsers({
      page,
      perPage: 200,
    });

    if (error) {
      throw error;
    }

    const matchedUser =
      data.users.find(
        (user) => user.email?.trim().toLowerCase() === normalizedEmail,
      ) ?? null;

    if (matchedUser) {
      return matchedUser;
    }

    if (!data.nextPage || data.users.length === 0) {
      return null;
    }

    page = data.nextPage;
  }
}

export async function findAuthIdentityByEmail(email: string) {
  const pool = getPostgresPool();
  const normalizedEmail = normalizeAuthEmail(email);
  const result = await pool.query<{ user_id: string; email: string }>(
    `
      select user_id, email
      from public.auth_user_identities
      where email_normalized = $1::text
      limit 1
    `,
    [normalizedEmail],
  );

  return result.rows[0] ?? null;
}

export async function upsertAuthIdentity(params: {
  userId: string;
  email: string;
}) {
  const pool = getPostgresPool();
  await pool.query(
    `
      insert into public.auth_user_identities (
        user_id,
        email
      )
      values ($1::uuid, $2::text)
      on conflict (user_id) do update
      set
        email = excluded.email,
        updated_at = timezone('utc', now())
    `,
    [params.userId, normalizeAuthEmail(params.email)],
  );
}

export async function persistAuthUserIdentity(params: {
  userId: string;
  email: string;
  username: string;
  displayName: string | null;
}) {
  const pool = getPostgresPool();
  const client = await pool.connect();

  try {
    await client.query("begin");
    await client.query(
      `
        insert into public.auth_user_identities (
          user_id,
          email
        )
        values ($1::uuid, $2::text)
        on conflict (user_id) do update
        set
          email = excluded.email,
          updated_at = timezone('utc', now())
      `,
      [params.userId, normalizeAuthEmail(params.email)],
    );

    await client.query(
      `
        insert into public.user_profiles (
          user_id,
          username,
          display_name,
          watchlist_visibility
        )
        values ($1::uuid, $2::text, $3::text, 'friends')
        on conflict (user_id) do update
        set
          username = excluded.username,
          display_name = excluded.display_name,
          updated_at = timezone('utc', now())
      `,
      [params.userId, params.username, params.displayName],
    );

    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

export async function isAuthEmailRegistered(email: string) {
  const cachedIdentity = await findAuthIdentityByEmail(email);
  if (cachedIdentity) {
    return true;
  }

  const user = await findAuthUserByEmail(email);
  if (user?.email) {
    await upsertAuthIdentity({
      userId: user.id,
      email: user.email,
    });
  }

  return user !== null;
}
