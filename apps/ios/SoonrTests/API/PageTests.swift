import Foundation
import Testing

@testable import Soonr

@Suite(.tags(.networking))
struct PageTests {
    private struct Item: Decodable, Equatable, Sendable {
        let id: String
    }

    private func decode(_ json: String) throws -> Page<Item> {
        try JSONDecoder().decode(Page<Item>.self, from: Data(json.utf8))
    }

    @Test
    func aPageCarriesItsItemsAndTheCursorAfterThem() throws {
        let page = try decode(#"{"items":[{"id":"a"},{"id":"b"}],"nextCursor":"cursor-2"}"#)

        #expect(page.items == [Item(id: "a"), Item(id: "b")])
        #expect(page.nextCursor == "cursor-2")
    }

    /// The end of a list, which is what stops the next request being made.
    @Test
    func aNullCursorMeansThereIsNothingAfterThisPage() throws {
        #expect(try decode(#"{"items":[],"nextCursor":null}"#).nextCursor == nil)
    }

    /// A server that stops sending the key means the same thing as null, and
    /// must not fail the page it came with.
    @Test
    func aMissingCursorIsTreatedAsTheEnd() throws {
        let page = try decode(#"{"items":[{"id":"a"}]}"#)

        #expect(page.items == [Item(id: "a")])
        #expect(page.nextCursor == nil)
    }

    @Test
    func aCursorOfAnUnexpectedTypeIsTreatedAsTheEndRatherThanFailing() throws {
        #expect(try decode(#"{"items":[],"nextCursor":7}"#).nextCursor == nil)
    }

    @Test
    func itemsAreRequired() {
        #expect(throws: (any Error).self) {
            try decode(#"{"nextCursor":"cursor-2"}"#)
        }
    }
}
