/// One page of a cursor-paged endpoint.
///
/// `apps/api` pages the same way everywhere — `{ items, nextCursor }`, ordered,
/// with an opaque cursor — so this is the shape of every paged response rather
/// than one endpoint's.
struct Page<Item: Sendable>: Sendable {
    let items: [Item]
    /// The cursor to ask for what follows, or `nil` at the end of the list.
    /// Opaque: it is the server's to interpret, and only ever passed back.
    let nextCursor: String?

    init(items: [Item], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

extension Page: Equatable where Item: Equatable {}

extension Page: Decodable where Item: Decodable {
    private enum CodingKeys: String, CodingKey {
        case items
        case nextCursor
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([Item].self, forKey: .items)
        // A server that stops sending the key means the same as sending null:
        // there is nothing after this.
        nextCursor = try? container.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}
