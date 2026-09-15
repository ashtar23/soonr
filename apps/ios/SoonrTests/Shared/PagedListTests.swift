import Foundation
import Testing

@testable import Soonr

@Suite
struct PagedListTests {
    private struct Row: Identifiable, Equatable, Sendable {
        let id: String
        var label: String = ""
    }

    private func page(_ ids: [String], next: String? = nil) -> Page<Row> {
        Page(items: ids.map { Row(id: $0) }, nextCursor: next)
    }

    // MARK: - Loading

    @Test
    func afreshListHoldsNothingAndAsksForNothing() {
        let list = PagedList<Row>()

        #expect(list.items.isEmpty)
        #expect(list.hasMore == false)
    }

    @Test
    func aFirstPageIsHeldInTheOrderItArrived() {
        let list = PagedList(page(["a", "b", "c"], next: "cursor-2"))

        #expect(list.items.map(\.id) == ["a", "b", "c"])
        #expect(list.nextCursor == "cursor-2")
        #expect(list.hasMore)
    }

    @Test
    func alaterPageGoesAfterTheOneBeforeIt() {
        var list = PagedList(page(["a", "b"], next: "cursor-2"))

        list.append(page(["c", "d"], next: "cursor-3"))

        #expect(list.items.map(\.id) == ["a", "b", "c", "d"])
        #expect(list.nextCursor == "cursor-3")
    }

    /// The end of the list is what stops the next request being made.
    @Test
    func apageWithoutACursorEndsTheList() {
        var list = PagedList(page(["a"], next: "cursor-2"))

        list.append(page(["b"]))

        #expect(list.hasMore == false)
    }

    /// A row inserted server-side while paging shifts everything after it down,
    /// so the same record legitimately arrives on two pages. Showing it twice
    /// would also break `List`, which needs identity to be unique.
    @Test
    func arowArrivingOnTwoPagesIsHeldOnce() {
        var list = PagedList(page(["a", "b"], next: "cursor-2"))

        list.append(page(["b", "c"], next: "cursor-3"))

        #expect(list.items.map(\.id) == ["a", "b", "c"])
    }

    @Test
    func apageThatRepeatsItselfIsStillHeldOnce() {
        let list = PagedList(page(["a", "a", "b"]))

        #expect(list.items.map(\.id) == ["a", "b"])
    }

    @Test
    func resettingForgetsEverythingHeldBefore() {
        var list = PagedList(page(["a", "b"], next: "cursor-2"))

        list.reset(to: page(["c"]))

        #expect(list.items.map(\.id) == ["c"])
        #expect(list.hasMore == false)
    }

    /// Reset clears identity as well as order, or a row that was dropped could
    /// never come back.
    @Test
    func arowRemovedByAResetCanBeLoadedAgain() {
        var list = PagedList(page(["a"], next: "cursor-2"))

        list.reset(to: page(["b"], next: "cursor-2"))
        list.append(page(["a"]))

        #expect(list.items.map(\.id) == ["b", "a"])
    }

    // MARK: - Reconciling

    @Test
    func areloadedFirstPagePutsNewRowsOnTop() {
        var list = PagedList(page(["b", "c"], next: "cursor-2"))
        list.append(page(["d"], next: "cursor-3"))

        list.reconcileFirstPage(page(["a", "b", "c"], next: "cursor-9"))

        #expect(list.items.map(\.id) == ["a", "b", "c", "d"])
    }

    @Test
    func severalNewRowsKeepTheOrderTheServerSentThem() {
        var list = PagedList(page(["c"], next: "cursor-2"))

        list.reconcileFirstPage(page(["a", "b", "c"]))

        #expect(list.items.map(\.id) == ["a", "b", "c"])
    }

    /// Pages already scrolled through are the whole point: dropping them would
    /// throw away what the reader is looking at.
    @Test
    func reconcilingKeepsPagesBeyondTheFirst() {
        var list = PagedList(page(["a"], next: "cursor-2"))
        list.append(page(["b", "c"], next: "cursor-3"))

        list.reconcileFirstPage(page(["a"], next: "cursor-2"))

        #expect(list.items.map(\.id) == ["a", "b", "c"])
    }

    @Test
    func areloadedRowIsUpdatedWhereItAlreadySits() {
        var list = PagedList(page(["a", "b"], next: "cursor-2"))
        list.append(page(["c"]))

        list.reconcileFirstPage(
            Page(items: [Row(id: "b", label: "changed")], nextCursor: "cursor-2")
        )

        #expect(list.items.map(\.id) == ["a", "b", "c"])
        #expect(list.items.first { $0.id == "b" }?.label == "changed")
    }

    /// Deeper cursors are anchored to a row rather than to a position, so rows
    /// appearing on top do not move what they point at.
    @Test
    func reconcilingLeavesTheCursorAlone() {
        var list = PagedList(page(["b"], next: "cursor-2"))

        list.reconcileFirstPage(page(["a", "b"], next: "cursor-nine"))

        #expect(list.nextCursor == "cursor-2")
    }

    @Test
    func reconcilingAnEmptyPageChangesNothing() {
        var list = PagedList(page(["a", "b"], next: "cursor-2"))

        list.reconcileFirstPage(Page(items: [], nextCursor: nil))

        #expect(list.items.map(\.id) == ["a", "b"])
        #expect(list.nextCursor == "cursor-2")
    }

    @Test
    func arowPrependedTwiceIsStillHeldOnce() {
        var list = PagedList(page(["b"], next: "cursor-2"))

        list.reconcileFirstPage(page(["a", "b"]))
        list.reconcileFirstPage(page(["a", "b"]))

        #expect(list.items.map(\.id) == ["a", "b"])
    }

    /// A row prepended by a reconcile must be known to the identity set, or the
    /// next page could append it a second time.
    @Test
    func arowAddedByAReconcileIsNotAppendedAgainLater() {
        var list = PagedList(page(["b"], next: "cursor-2"))
        list.reconcileFirstPage(page(["a", "b"]))

        list.append(page(["a", "c"]))

        #expect(list.items.map(\.id) == ["a", "b", "c"])
    }

    // MARK: - Local changes

    @Test
    func updatingARowLeavesItWhereItIs() {
        var list = PagedList(page(["a", "b", "c"]))

        list.update(Row(id: "b", label: "read"))

        #expect(list.items.map(\.id) == ["a", "b", "c"])
        #expect(list.items[1].label == "read")
    }

    @Test
    func updatingARowThatIsNotHeldChangesNothing() {
        var list = PagedList(page(["a"]))

        list.update(Row(id: "zzz", label: "read"))

        #expect(list.items == [Row(id: "a")])
    }

    @Test
    func everyRowCanBeChangedAtOnce() {
        var list = PagedList(page(["a", "b"]))

        list.updateAll { Row(id: $0.id, label: "read") }

        #expect(list.items.allSatisfy { $0.label == "read" })
    }

    @Test
    func aRowAddedHereGoesOnTop() {
        var list = PagedList(page(["b", "c"], next: "cursor-2"))

        list.prepend(Row(id: "a"))

        #expect(list.items.map(\.id) == ["a", "b", "c"])
    }

    @Test
    func aRowAlreadyHeldIsNotAddedTwice() {
        var list = PagedList(page(["a", "b"]))

        list.prepend(Row(id: "b"))

        #expect(list.items.map(\.id) == ["a", "b"])
    }

    /// A row added here must be known to identity, or the page it really lives
    /// on would show it a second time when it loads.
    @Test
    func aRowAddedHereIsNotAppendedAgainByALaterPage() {
        var list = PagedList(page(["b"], next: "cursor-2"))
        list.prepend(Row(id: "a"))

        list.append(page(["a", "c"]))

        #expect(list.items.map(\.id) == ["a", "b", "c"])
    }

    @Test
    func aRemovedRowIsGone() {
        var list = PagedList(page(["a", "b", "c"]))

        list.removeAll { $0.id == "b" }

        #expect(list.items.map(\.id) == ["a", "c"])
    }

    /// Removing has to forget as well as drop, or saving the same title again
    /// would be rejected as a duplicate and never reappear.
    @Test
    func aRemovedRowCanComeBack() {
        var list = PagedList(page(["a", "b"]))
        list.removeAll { $0.id == "b" }

        list.prepend(Row(id: "b"))

        #expect(list.items.map(\.id) == ["b", "a"])
    }

    @Test
    func removingSomethingNotHeldChangesNothing() {
        var list = PagedList(page(["a"], next: "cursor-2"))

        list.removeAll { $0.id == "zzz" }

        #expect(list.items.map(\.id) == ["a"])
        #expect(list.nextCursor == "cursor-2")
    }

    /// A refused removal puts the row back where it was, not at the top.
    @Test
    func aRowPutBackReturnsToItsPlace() {
        var list = PagedList(page(["a", "b", "c"]))
        list.removeAll { $0.id == "b" }

        list.insert(Row(id: "b"), at: 1)

        #expect(list.items.map(\.id) == ["a", "b", "c"])
    }

    /// Rows can go while the request is out, leaving the old index past the
    /// end; the row still comes back rather than crashing.
    @Test
    func aRowPutBackPastTheEndGoesLast() {
        var list = PagedList(page(["a", "b", "c"]))
        list.removeAll { $0.id != "a" }

        list.insert(Row(id: "c"), at: 2)

        #expect(list.items.map(\.id) == ["a", "c"])
    }

    @Test
    func aRowAlreadyHeldIsNotPutBackTwice() {
        var list = PagedList(page(["a", "b"]))

        list.insert(Row(id: "b"), at: 0)

        #expect(list.items.map(\.id) == ["a", "b"])
    }

    // MARK: - Cost

    /// Loading deep must not get slower the deeper it goes: identity is a set
    /// lookup, so this is linear rather than quadratic. It would not finish in
    /// reasonable time if `items.contains` were used instead.
    @Test
    func loadingManyPagesStaysLinear() {
        var list = PagedList<Row>()
        let pageSize = 20

        for pageIndex in 0..<500 {
            let ids = (0..<pageSize).map { "row-\(pageIndex * pageSize + $0)" }
            list.append(page(ids, next: "cursor-\(pageIndex)"))
        }

        #expect(list.items.count == 10_000)
        #expect(list.items.first?.id == "row-0")
        #expect(list.items.last?.id == "row-9999")
    }
}
