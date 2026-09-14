import { getPostgresPool } from "../postgres";
import { validateUsername } from "./identity";

export type WatchlistVisibility = "private" | "friends" | "public";

export interface ProfileEdit {
  // Absent means leave it alone. Present and null means clear it.
  username?: string;
  displayName?: string | null;
  bio?: string | null;
  watchlistVisibility?: WatchlistVisibility;
}

export interface EditedProfile {
  userId: string;
  username: string | null;
  displayName: string | null;
  avatarUrl: string | null;
  bio: string | null;
  watchlistVisibility: WatchlistVisibility;
}

export interface ProfileEditStore {
  updateProfile: (params: {
    userId: string;
    username?: string;
    displayName?: string | null;
    bio?: string | null;
    watchlistVisibility?: WatchlistVisibility;
  }) => Promise<EditedProfile | null>;
}

export type ProfileEditFailure =
  | "invalid_username"
  | "reserved_username"
  | "username_taken"
  | "bio_too_long"
  | "display_name_too_long"
  | "no_profile";

export class ProfileEditError extends Error {
  constructor(readonly reason: ProfileEditFailure, message: string) {
    super(message);
    this.name = "ProfileEditError";
  }
}

// Long enough to say something, short enough that a list of people stays a
// list rather than an essay each.
export const MAXIMUM_BIO_LENGTH = 280;
export const MAXIMUM_DISPLAY_NAME_LENGTH = 60;

/**
 * Changes the parts of a profile its owner is allowed to change.
 *
 * Everything under `/profile` reads; nothing writes, so a profile could only
 * ever hold what signup put there. An account created before signup asked for
 * a username has none and no way to gain one, which also means nobody can
 * find it or link to it.
 *
 * A field left out is left alone, which is what makes this safe to call from a
 * form that edits one thing. Sending null clears the field, and the difference
 * between "not mentioned" and "cleared" is the whole reason this takes a patch
 * rather than a whole profile.
 */
export async function editProfile(
  deps: { store: ProfileEditStore },
  params: { userId: string; edit: ProfileEdit },
): Promise<EditedProfile> {
  const edit = normalizeEdit(params.edit);

  const updated = await deps.store
    .updateProfile({ userId: params.userId, ...edit })
    .catch((error: unknown) => {
      // The database is the authority on uniqueness: two people can pass the
      // availability check at the same moment and only one can have the name.
      if (isUsernameTakenError(error)) {
        throw new ProfileEditError(
          "username_taken",
          "This username is already taken.",
        );
      }

      throw error;
    });

  if (!updated) {
    throw new ProfileEditError(
      "no_profile",
      "This account has no profile to edit.",
    );
  }

  return updated;
}

function normalizeEdit(edit: ProfileEdit): ProfileEdit {
  const normalized: ProfileEdit = {};

  if (edit.username !== undefined) {
    const result = validateUsername(edit.username);

    switch (result.status) {
      case "invalid":
        throw new ProfileEditError("invalid_username", "Username is invalid.");
      case "reserved":
        throw new ProfileEditError(
          "reserved_username",
          "Username is reserved.",
        );
      case "valid":
        normalized.username = result.normalizedUsername;
        break;
    }
  }

  if (edit.displayName !== undefined) {
    normalized.displayName = trimmedOrNull(
      edit.displayName,
      MAXIMUM_DISPLAY_NAME_LENGTH,
      "display_name_too_long",
      "Display name is too long.",
    );
  }

  if (edit.bio !== undefined) {
    normalized.bio = trimmedOrNull(
      edit.bio,
      MAXIMUM_BIO_LENGTH,
      "bio_too_long",
      "Bio is too long.",
    );
  }

  if (edit.watchlistVisibility !== undefined) {
    normalized.watchlistVisibility = edit.watchlistVisibility;
  }

  return normalized;
}

/**
 * Whitespace is not a display name, so a field of it clears the field rather
 * than storing spaces that every screen then has to cope with.
 */
function trimmedOrNull(
  value: string | null,
  maximumLength: number,
  reason: ProfileEditFailure,
  message: string,
): string | null {
  if (value === null) {
    return null;
  }

  const trimmed = value.trim();

  if (trimmed.length > maximumLength) {
    throw new ProfileEditError(reason, message);
  }

  return trimmed.length === 0 ? null : trimmed;
}

function isUsernameTakenError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "constraint" in error &&
    (error as { constraint?: string }).constraint ===
      "user_profiles_username_normalized_key"
  );
}

export const postgresProfileEditStore: ProfileEditStore = {
  async updateProfile({
    userId,
    username,
    displayName,
    bio,
    watchlistVisibility,
  }) {
    const pool = getPostgresPool();
    // A flag beside each value rather than coalescing, because null is a real
    // value here: it clears the field, and "not mentioned" has to mean
    // something different from "cleared". One statement, so a form cannot
    // half-apply.
    //
    // `username_normalized` is generated from `username` and is not set here —
    // the database refuses to be told what it already knows how to work out.
    const result = await pool.query<{
      user_id: string;
      username: string | null;
      display_name: string | null;
      avatar_url: string | null;
      bio: string | null;
      watchlist_visibility: WatchlistVisibility;
    }>(
      `
        update public.user_profiles
        set
          username = case when $2::boolean then $3::text else username end,
          display_name = case when $4::boolean then $5::text else display_name end,
          bio = case when $6::boolean then $7::text else bio end,
          watchlist_visibility = case
            when $8::boolean then $9::text else watchlist_visibility
          end,
          updated_at = timezone('utc', now())
        where user_id = $1::uuid
        returning
          user_id, username, display_name, avatar_url, bio, watchlist_visibility
      `,
      [
        userId,
        username !== undefined,
        username ?? null,
        displayName !== undefined,
        displayName ?? null,
        bio !== undefined,
        bio ?? null,
        watchlistVisibility !== undefined,
        watchlistVisibility ?? null,
      ],
    );

    const row = result.rows[0];
    if (!row) {
      return null;
    }

    return {
      userId: row.user_id,
      username: row.username,
      displayName: row.display_name,
      avatarUrl: row.avatar_url,
      bio: row.bio,
      watchlistVisibility: row.watchlist_visibility,
    };
  },
};
