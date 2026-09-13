/// What it takes to open the details screen: the id its request needs, and a
/// name to show in the navigation bar until the request answers.
///
/// A notification knows only this much about the title it points at, so the
/// screen asks for this rather than a whole `TitleSummary` it would have to be
/// handed a hollow copy of.
struct TitleDestination: Hashable, Sendable {
    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ summary: TitleSummary) {
        self.init(id: summary.id, name: summary.name)
    }
}
