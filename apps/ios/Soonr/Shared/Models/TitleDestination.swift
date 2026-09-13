/// The id the details request needs, plus a name for its navigation bar until
/// that request answers.
///
/// A notification knows only this much about the title it points at, so the
/// screen asks for this rather than a `TitleSummary` it would be handed a
/// hollow copy of.
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
