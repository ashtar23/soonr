import { Type } from "@sinclair/typebox";
import { WatchlistListResultSchema } from "./watchlist";

export const UsernameAvailabilityQuerySchema = Type.Object({
  username: Type.String({ minLength: 1 }),
});

export const UsernameAvailabilityResultSchema = Type.Object({
  available: Type.Boolean(),
  reason: Type.Optional(
    Type.Union([
      Type.Literal("taken"),
      Type.Literal("invalid"),
      Type.Literal("reserved"),
    ]),
  ),
});

export const ProfileParamsSchema = Type.Object({
  userId: Type.String({ minLength: 1 }),
});

export const ProfileListQuerySchema = Type.Object({
  cursor: Type.Optional(Type.String()),
  limit: Type.Optional(Type.String()),
});

export const ProfileRelationshipSchema = Type.Object({
  following: Type.Boolean(),
  followedByViewer: Type.Boolean(),
  isFriend: Type.Boolean(),
});

export const ProfileSummarySchema = Type.Object({
  userId: Type.String(),
  username: Type.Union([Type.String(), Type.Null()]),
  displayName: Type.Union([Type.String(), Type.Null()]),
  avatarUrl: Type.Union([Type.String(), Type.Null()]),
  bio: Type.Union([Type.String(), Type.Null()]),
  watchlistVisibility: Type.Union([
    Type.Literal("private"),
    Type.Literal("friends"),
    Type.Literal("public"),
  ]),
});

export const ProfileWatchlistPreviewItemSchema = Type.Object({
  id: Type.String(),
  titleId: Type.String(),
  name: Type.String(),
  addedAt: Type.String(),
});

export const ProfileOverviewResultSchema = Type.Object({
  profile: ProfileSummarySchema,
  relationship: ProfileRelationshipSchema,
  counts: Type.Object({
    followers: Type.Integer(),
    following: Type.Integer(),
    friends: Type.Integer(),
  }),
  canViewWatchlist: Type.Boolean(),
  watchlistPreview: Type.Array(ProfileWatchlistPreviewItemSchema),
  recentAdditionsPreview: Type.Array(ProfileWatchlistPreviewItemSchema),
});

export const ProfileConnectionSummarySchema = Type.Object({
  userId: Type.String(),
  username: Type.Union([Type.String(), Type.Null()]),
  displayName: Type.Union([Type.String(), Type.Null()]),
  avatarUrl: Type.Union([Type.String(), Type.Null()]),
  relationship: ProfileRelationshipSchema,
});

export const ProfileConnectionsListResultSchema = Type.Object({
  items: Type.Array(ProfileConnectionSummarySchema),
  nextCursor: Type.Union([Type.String(), Type.Null()]),
});

export { WatchlistListResultSchema as ProfileWatchlistListResultSchema };

/**
 * A patch, not a profile: a field left out is left alone, and sending null
 * clears it. A form that edits one thing sends one thing.
 */
export const ProfileEditBodySchema = Type.Object({
  username: Type.Optional(Type.String({ minLength: 1 })),
  displayName: Type.Optional(Type.Union([Type.String(), Type.Null()])),
  bio: Type.Optional(Type.Union([Type.String(), Type.Null()])),
  watchlistVisibility: Type.Optional(
    Type.Union([
      Type.Literal("private"),
      Type.Literal("friends"),
      Type.Literal("public"),
    ]),
  ),
});

export const ProfileEditResultSchema = Type.Object({
  profile: Type.Object({
    userId: Type.String(),
    username: Type.Union([Type.String(), Type.Null()]),
    displayName: Type.Union([Type.String(), Type.Null()]),
    avatarUrl: Type.Union([Type.String(), Type.Null()]),
    bio: Type.Union([Type.String(), Type.Null()]),
    watchlistVisibility: Type.Union([
      Type.Literal("private"),
      Type.Literal("friends"),
      Type.Literal("public"),
    ]),
  }),
});
