/// One saved title. `releases` is part of the payload but nothing on this
/// screen shows per-platform dates, so it is not decoded.
struct WatchlistEntry: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    let title: TitleSummary
    let addedAt: String
}
