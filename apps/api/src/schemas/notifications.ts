import { Type } from "@sinclair/typebox";
import {
  notificationDestinationKindValues,
  notificationEventTypeValues,
  notificationTimingPresetValues,
} from "@repo/types";

export const NotificationTimingPresetSchema = Type.Union(
  notificationTimingPresetValues.map((value) => Type.Literal(value)),
);

const NotificationEventTypeSchema = Type.Union(
  notificationEventTypeValues.map((value) => Type.Literal(value)),
);

const NotificationDestinationKindSchema = Type.Union(
  notificationDestinationKindValues.map((value) => Type.Literal(value)),
);

const ReleaseDateChangedNotificationPayloadSchema = Type.Object({
  previousReleaseDate: Type.Union([Type.String(), Type.Null()]),
  nextReleaseDate: Type.Union([Type.String(), Type.Null()]),
});

// Optional because a stored payload may not carry a preset this build can
// read, and dropping it is better than failing the response or inventing one.
// Clients read the dates; nothing renders the preset.
const ReleaseApproachingNotificationPayloadSchema = Type.Object({
  targetReleaseDate: Type.Union([Type.String(), Type.Null()]),
  timingPreset: Type.Optional(NotificationTimingPresetSchema),
});

export const NotificationPayloadSchema = Type.Union([
  ReleaseDateChangedNotificationPayloadSchema,
  ReleaseApproachingNotificationPayloadSchema,
]);

export const NotificationRecordSchema = Type.Object({
  id: Type.String(),
  titleId: Type.String(),
  eventType: NotificationEventTypeSchema,
  destinationKind: NotificationDestinationKindSchema,
  destinationTitleId: Type.String(),
  titleName: Type.String(),
  titleArtworkUrl: Type.Union([Type.String(), Type.Null()]),
  message: Type.String(),
  subtitle: Type.Union([Type.String(), Type.Null()]),
  payload: NotificationPayloadSchema,
  createdAt: Type.String(),
  readAt: Type.Union([Type.String(), Type.Null()]),
});

export const NotificationRecordListResultSchema = Type.Object({
  items: Type.Array(NotificationRecordSchema),
  nextCursor: Type.Union([Type.String(), Type.Null()]),
});

export const NotificationUnreadCountResultSchema = Type.Object({
  unreadCount: Type.Number(),
});

export const NotificationPreferencesSchema = Type.Object({
  channels: Type.Object({
    inApp: Type.Boolean(),
    push: Type.Boolean(),
  }),
  events: Type.Object({
    releaseDateChanged: Type.Boolean(),
    releaseApproaching: Type.Boolean(),
  }),
  timingPresets: Type.Array(NotificationTimingPresetSchema),
  updatedAt: Type.String(),
});

export const NotificationPreferencesResultSchema = Type.Object({
  preferences: NotificationPreferencesSchema,
});

export const NotificationsQuerySchema = Type.Object({
  cursor: Type.Optional(Type.String()),
  limit: Type.Optional(Type.String()),
});

export const NotificationReadBodySchema = Type.Object({
  notificationId: Type.String({ minLength: 1 }),
});

export const MarkNotificationReadResultSchema = Type.Object({
  notification: NotificationRecordSchema,
});

export const MarkAllNotificationsReadResultSchema = Type.Object({
  markedCount: Type.Number(),
});

export const UpdateNotificationPreferencesBodySchema = Type.Object({
  channels: Type.Object({
    inApp: Type.Boolean(),
    push: Type.Boolean(),
  }),
  events: Type.Object({
    releaseDateChanged: Type.Boolean(),
    releaseApproaching: Type.Boolean(),
  }),
  timingPresets: Type.Array(NotificationTimingPresetSchema),
});

const DevicePlatformSchema = Type.Literal("ios");

const DeviceEnvironmentSchema = Type.Union([
  Type.Literal("sandbox"),
  Type.Literal("production"),
]);

export const DeviceSchema = Type.Object({
  token: Type.String(),
  platform: DevicePlatformSchema,
  environment: DeviceEnvironmentSchema,
});

export const DeviceRegistrationBodySchema = DeviceSchema;

export const DeviceParamsSchema = Type.Object({
  token: Type.String(),
});

export const DeviceRegistrationResultSchema = Type.Object({
  device: DeviceSchema,
});

export const DeviceRemovedResultSchema = Type.Object({
  removed: Type.Boolean(),
});
