import Foundation

#if DEBUG

    /// Performs no network requests.
    struct PreviewNotifications:
        NotificationsReading, NotificationPreferencesProviding, DeviceRegistering
    {
        var records: [NotificationRecord] = [.previewUnread, .previewRead]
        var preferences = NotificationPreferences(
            channels: .init(inApp: true, push: false),
            events: .init(releaseDateChanged: true, releaseApproaching: true),
            timingPresets: [.onDay, .days7Before]
        )

        func notifications(
            after _: String?,
            unreadOnly: Bool
        ) async throws -> Page<NotificationRecord> {
            Page(items: unreadOnly ? records.filter { $0.isRead == false } : records)
        }

        func notifications(about titleID: String) async throws -> [NotificationRecord] {
            records.filter { $0.destinationTitleID == titleID }
        }

        func unreadNotificationCount() async throws -> Int {
            records.filter { $0.isRead == false }.count
        }

        func markNotificationRead(id: String) async throws -> NotificationRecord {
            guard let record = records.first(where: { $0.id == id }) else {
                throw PreviewNotificationsError.unknownNotification
            }

            return NotificationRecord(record, readAt: ISO8601DateFormatter().string(from: .now))
        }

        func markAllNotificationsRead() async throws -> Int {
            records.filter { $0.isRead == false }.count
        }

        func notificationPreferences() async throws -> NotificationPreferences {
            preferences
        }

        func registerDevice(token: String, environment: PushEnvironment) async throws {}

        func unregisterDevice(token: String) async throws {}

        func updateNotificationPreferences(
            _ preferences: NotificationPreferences
        ) async throws -> NotificationPreferences {
            preferences
        }
    }

    enum PreviewNotificationsError: Error {
        case unknownNotification
    }

    extension NotificationRecord {
        static let previewUnread = NotificationRecord(
            id: "preview-unread",
            eventType: .releaseApproaching,
            destinationTitleID: TitleSummary.previewUpcoming.id,
            titleName: TitleSummary.previewUpcoming.name,
            titleArtworkURL: nil,
            message: "Release approaching",
            subtitle: "Releases in 7 days on January 5, 2026",
            payload: .releaseApproaching(
                targetReleaseDate: TitleSummary.previewUpcoming.earliestReleaseDate
            ),
            createdAt: ISO8601DateFormatter().string(from: .now.addingTimeInterval(-2 * 60 * 60)),
            readAt: nil
        )

        static let previewRead = NotificationRecord(
            id: "preview-read",
            eventType: .releaseDateChanged,
            destinationTitleID: TitleSummary.preview.id,
            titleName: TitleSummary.preview.name,
            titleArtworkURL: nil,
            message: "Release date changed",
            subtitle: "Now releases Nov 19, 2026",
            payload: .releaseDateChanged(nextReleaseDate: "2026-11-19"),
            createdAt: ISO8601DateFormatter().string(
                from: .now.addingTimeInterval(-3 * 24 * 60 * 60)),
            readAt: ISO8601DateFormatter().string(from: .now.addingTimeInterval(-2 * 24 * 60 * 60))
        )
    }

#endif
