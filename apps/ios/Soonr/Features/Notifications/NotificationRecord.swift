import Foundation

/// `Hashable` because the list navigates with the record itself.
struct NotificationRecord: Decodable, Hashable, Sendable, Identifiable {
    enum EventType: String, Hashable, Sendable {
        case releaseDateChanged = "release_date_changed"
        case releaseApproaching = "release_approaching"
        case unknown
    }

    let id: String
    let eventType: EventType
    /// What the row opens. `titleId` is what the notification is about;
    /// these are the same today but the API keeps them apart.
    let destinationTitleID: String
    let titleName: String
    let titleArtworkURL: URL?
    let message: String
    let subtitle: String?
    /// What the event was about, in data. The server also writes a sentence
    /// about it, but that sentence is frozen at the moment it was generated.
    let payload: NotificationPayload
    let createdAt: String
    let readAt: String?

    var isRead: Bool {
        readAt != nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case eventType
        case destinationTitleID = "destinationTitleId"
        case titleName
        case titleArtworkURL = "titleArtworkUrl"
        case message
        case subtitle
        case payload
        case createdAt
        case readAt
    }
}

extension NotificationRecord {
    /// The same notification with a different read state.
    init(_ other: NotificationRecord, readAt: String?) {
        self.init(
            id: other.id,
            eventType: other.eventType,
            destinationTitleID: other.destinationTitleID,
            titleName: other.titleName,
            titleArtworkURL: other.titleArtworkURL,
            message: other.message,
            subtitle: other.subtitle,
            payload: other.payload,
            createdAt: other.createdAt,
            readAt: readAt
        )
    }
}

extension NotificationRecord.EventType: Decodable {
    /// A new event type must not fail the whole list.
    init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: rawValue) ?? .unknown
    }
}

struct NotificationPreferences: Codable, Equatable, Sendable {
    enum TimingPreset: String, Codable, Equatable, Sendable, CaseIterable {
        case onDay = "on_day"
        case hours24Before = "hours_24_before"
        case days7Before = "days_7_before"
        case days30Before = "days_30_before"

        /// Furthest ahead first: the order a release approaches in, which is
        /// also the order the screen lists them in.
        static let inApproachOrder: [Self] = [
            .days30Before, .days7Before, .hours24Before, .onDay,
        ]
    }

    struct Channels: Codable, Equatable, Sendable {
        var inApp: Bool
        var push: Bool
    }

    struct Events: Codable, Equatable, Sendable {
        var releaseDateChanged: Bool
        var releaseApproaching: Bool
    }

    var channels: Channels
    var events: Events
    var timingPresets: [TimingPreset]

    /// Presets the client does not know are dropped rather than failing the
    /// payload: it cannot offer a switch for something it cannot name, but it
    /// can still show the rest.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        channels = try container.decode(Channels.self, forKey: .channels)
        events = try container.decode(Events.self, forKey: .events)
        timingPresets = try container.decode([String].self, forKey: .timingPresets)
            .compactMap(TimingPreset.init(rawValue:))
    }

    init(channels: Channels, events: Events, timingPresets: [TimingPreset]) {
        self.channels = channels
        self.events = events
        self.timingPresets = timingPresets
    }

    /// Adds or removes one timing preset, keeping the canonical order so a
    /// saved copy coming back does not reshuffle the screen.
    ///
    /// The list never empties: the server replaces an empty one with its own
    /// default, so clearing the last preset put the checkmark straight back
    /// and made the tap look broken.
    mutating func toggleTimingPreset(_ preset: TimingPreset) {
        if timingPresets.contains(preset) {
            guard timingPresets.count > 1 else {
                return
            }

            timingPresets.removeAll { $0 == preset }
        } else {
            timingPresets = TimingPreset.inApproachOrder.filter {
                $0 == preset || timingPresets.contains($0)
            }
        }
    }

    /// What the server assumes for an account that has never saved any: the
    /// same values `notification-generation` falls back to.
    static let `default` = NotificationPreferences(
        channels: Channels(inApp: true, push: false),
        events: Events(releaseDateChanged: true, releaseApproaching: true),
        timingPresets: [.onDay]
    )
}
