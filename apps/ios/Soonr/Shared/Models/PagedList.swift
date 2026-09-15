/// The accumulated pages of a cursor-paged list.
///
/// A pure value: it holds order and identity and nothing else, so every rule
/// below is testable without a network, a store, or a screen.
///
/// Two costs are deliberate, because they are what makes a long list stay
/// smooth:
///
/// - **Membership is a set, never a scan.** Appending a page checks each
///   arrival against `identifiers` in constant time. Asking `items.contains`
///   instead would make loading page *n* cost *n* passes over everything
///   already held, which is the quiet way a list gets slower the further it is
///   scrolled.
/// - **Reconciling touches the array once.** Updating in place and prepending
///   what is new is a single pass, not a lookup per row.
///
/// Identity also decides what SwiftUI does with the result: `List` diffs on
/// `id`, so appending costs work for the new rows only, while handing it a
/// freshly built array of everything forces a full diff and drops the scroll
/// position. Nothing here ever rebuilds the array wholesale.
struct PagedList<Item: Identifiable & Equatable & Sendable>: Equatable, Sendable
where Item.ID: Sendable {
    private(set) var items: [Item] = []
    /// The cursor for the page after the last one loaded, or `nil` when the
    /// end has been reached — which is also how "stop asking" is expressed.
    private(set) var nextCursor: String?

    private var identifiers: Set<Item.ID> = []

    var hasMore: Bool {
        nextCursor != nil
    }

    init() {}

    init(_ page: Page<Item>) {
        reset(to: page)
    }

    /// A fresh first page, replacing everything held.
    mutating func reset(to page: Page<Item>) {
        items = []
        identifiers = []
        nextCursor = page.nextCursor
        add(page.items)
    }

    /// The next page, after the last one held.
    ///
    /// Duplicates are dropped rather than appended: a row inserted server-side
    /// while paging shifts everything after it down, so the same record can
    /// legitimately arrive twice. Keeping both would show it twice and, worse,
    /// break `List`'s diffing, which requires unique identity.
    mutating func append(_ page: Page<Item>) {
        nextCursor = page.nextCursor
        add(page.items)
    }

    /// A reloaded first page, merged into what is already held.
    ///
    /// Answers a change the server reported without discarding the pages
    /// already scrolled through: rows still present are updated where they
    /// stand, and rows that are new go on top, which is where the server's own
    /// newest-first order puts them.
    ///
    /// `nextCursor` is deliberately left alone. Cursors here are anchored to a
    /// row's timestamp and id rather than to an offset, so inserting rows at
    /// the top does not move what a deeper cursor points at — the reason
    /// cursor paging is worth its extra complexity over `offset`.
    mutating func reconcileFirstPage(_ page: Page<Item>) {
        var arriving = Dictionary(
            page.items.map { ($0.id, $0) },
            uniquingKeysWith: { _, last in last }
        )

        items = items.map { held in
            arriving.removeValue(forKey: held.id) ?? held
        }

        // Whatever the pass above did not claim was not held before.
        let added = page.items.filter { arriving[$0.id] != nil }
        items.insert(contentsOf: added, at: 0)
        identifiers.formUnion(added.map(\.id))
    }

    /// Adds a row at the top, for one created here rather than loaded. Does
    /// nothing if it is already held, so saving something twice cannot show it
    /// twice.
    mutating func prepend(_ item: Item) {
        guard identifiers.contains(item.id) == false else {
            return
        }

        identifiers.insert(item.id)
        items.insert(item, at: 0)
    }

    /// Removes rows, and forgets them: identity has to go with the row, or the
    /// same row added again would be rejected as a duplicate and never
    /// reappear.
    ///
    /// Takes a predicate rather than an id because a row is not always removed
    /// by the identity it is listed under — a watchlist entry is identified by
    /// the entry, and removed by the title it holds.
    mutating func removeAll(where shouldRemove: (Item) -> Bool) {
        var removed = false

        for item in items where shouldRemove(item) {
            identifiers.remove(item.id)
            removed = true
        }

        guard removed else {
            return
        }

        items.removeAll(where: shouldRemove)
    }

    /// Puts one row back where it was, for a removal the server refused.
    ///
    /// The position is clamped rather than trusted: rows can have come and gone
    /// while the request was out, so the old index may now be past the end.
    mutating func insert(_ item: Item, at index: Int) {
        guard identifiers.contains(item.id) == false else {
            return
        }

        identifiers.insert(item.id)
        items.insert(item, at: min(max(index, 0), items.count))
    }

    /// Replaces one row, wherever it sits. Used for a change made here rather
    /// than one the server reported.
    mutating func update(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        items[index] = item
    }

    mutating func updateAll(_ transform: (Item) -> Item) {
        items = items.map(transform)
    }

    private mutating func add(_ arriving: [Item]) {
        for item in arriving where identifiers.contains(item.id) == false {
            identifiers.insert(item.id)
            items.append(item)
        }
    }
}
