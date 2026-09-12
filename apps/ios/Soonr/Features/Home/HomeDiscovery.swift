import Foundation

struct HomeDiscovery: Decodable, Equatable, Sendable {
    let upcoming: [TitleSummary]
    let latest: [TitleSummary]
    let popular: [TitleSummary]

    var isEmpty: Bool {
        rails.allSatisfy { $0.titles.isEmpty }
    }

    /// The rails in the order Home presents them, skipping empty ones.
    var populatedRails: [HomeRail] {
        rails.filter { $0.titles.isEmpty == false }
    }

    private var rails: [HomeRail] {
        [
            HomeRail(section: .upcoming, titles: upcoming),
            HomeRail(section: .latest, titles: latest),
            HomeRail(section: .popular, titles: popular),
        ]
    }
}

struct HomeRail: Equatable, Identifiable, Sendable {
    enum Section: String, Sendable {
        case upcoming
        case latest
        case popular

        var title: String {
            switch self {
            case .upcoming: "Coming soon"
            case .latest: "Just released"
            case .popular: "Worth watching"
            }
        }
    }

    let section: Section
    let titles: [TitleSummary]

    var id: String { section.rawValue }
}
