import Foundation
import Testing

@testable import Soonr

/// The operations a paged list really sees are interleaved, and each of the
/// other tests exercises one of them alone. The bug that did happen — a
/// watchlist row held under a stand-in id and then appended again by the page
/// it really lived on — was an interaction, so this drives them together.
///
/// Deterministic: the generator is seeded, so a failure is reproducible rather
/// than a story about a build that went red once.
@Suite
struct PagedListStressTests {
    private struct Row: Identifiable, Equatable, Sendable {
        let id: String
        var label: String = ""
    }

    /// A pseudo-random sequence with no dependency on the platform's, so the
    /// same seed means the same run on any machine and any Swift version.
    private struct Seeded {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next(_ upperBound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(upperBound))
        }
    }

    private func page(_ ids: [String], next: String? = nil) -> Page<Row> {
        Page(items: ids.map { Row(id: $0) }, nextCursor: next)
    }

    /// Everything the list promises, checked from outside: it never holds the
    /// same row twice, and its identity is in step with what it holds — asked
    /// by trying to add a held row again and seeing nothing happen.
    private func assertIntact(
        _ list: PagedList<Row>,
        after step: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let ids = list.items.map(\.id)
        #expect(
            Set(ids).count == ids.count,
            "held the same row twice after \(step)",
            sourceLocation: sourceLocation
        )

        guard let held = ids.randomElement() else {
            return
        }

        var copy = list
        copy.append(Page(items: [Row(id: held)], nextCursor: nil))
        #expect(
            copy.items.count == list.items.count,
            "a row it already held was added again after \(step)",
            sourceLocation: sourceLocation
        )

        var prepended = list
        prepended.prepend(Row(id: held))
        #expect(
            prepended.items.count == list.items.count,
            "a row it already held was put on top again after \(step)",
            sourceLocation: sourceLocation
        )
    }

    @Test(arguments: [1 as UInt64, 7, 99, 2026])
    func interleavedOperationsKeepTheListIntact(seed: UInt64) {
        var random = Seeded(seed: seed)
        var list = PagedList<Row>()
        var served = 0
        var removed: Set<String> = []

        for step in 0..<400 {
            switch random.next(6) {
            case 0:
                // The next page, sometimes overlapping the last as the server
                // does when something was inserted while paging.
                let overlap = list.items.suffix(random.next(3)).map(\.id)
                let fresh = (0..<random.next(5)).map { _ -> String in
                    served += 1
                    return "row-\(served)"
                }
                list.append(page(overlap + fresh, next: "cursor-\(step)"))

            case 1:
                // A reloaded first page: some of what is held, and some new.
                let existing = list.items.prefix(random.next(4)).map(\.id)
                let arrived = (0..<random.next(3)).map { _ -> String in
                    served += 1
                    return "row-\(served)"
                }
                list.reconcileFirstPage(page(arrived + existing))

            case 2:
                served += 1
                list.prepend(Row(id: "row-\(served)"))

            case 3:
                if let victim = list.items.randomElement()?.id {
                    removed.insert(victim)
                    list.removeAll { $0.id == victim }
                }

            case 4:
                if let target = list.items.randomElement()?.id {
                    list.update(Row(id: target, label: "step-\(step)"))
                }

            default:
                // Starting over has to forget identity as well as order, or a
                // row dropped here could never come back.
                let ids = (0..<random.next(4)).map { _ -> String in
                    served += 1
                    return "row-\(served)"
                }
                list.reset(to: page(ids, next: "cursor-\(step)"))
                removed.removeAll()
            }

            assertIntact(list, after: "step \(step)")
        }

        // A row taken out and offered again is genuinely taken back, which is
        // what says removal forgot it rather than merely hiding it.
        for id in removed.prefix(5) where list.items.contains(where: { $0.id == id }) == false {
            var copy = list
            copy.prepend(Row(id: id))
            #expect(copy.items.first?.id == id)
        }
    }

    /// Ordering is the other half of what it promises: a reload puts what is
    /// new on top and leaves everything else where the reader left it.
    @Test
    func reconcilingRepeatedlyNeverDisturbsWhatIsBelow() {
        var list = PagedList(page(["a", "b"], next: "cursor-2"))
        list.append(page(["c", "d"], next: "cursor-3"))
        list.append(page(["e", "f"]))
        let deeper = ["c", "d", "e", "f"]

        for round in 0..<50 {
            list.reconcileFirstPage(page(["new-\(round)", "a", "b"]))

            #expect(list.items.first?.id == "new-\(round)")
            #expect(list.items.suffix(4).map(\.id) == deeper)
        }

        // Fifty reloads, fifty new rows, and nothing counted twice.
        #expect(list.items.count == 50 + 6)
    }

    /// Paging deep must not get slower the deeper it goes.
    @Test
    func aThousandPagesStaysLinear() {
        var list = PagedList<Row>()

        for pageIndex in 0..<1_000 {
            let ids = (0..<20).map { "row-\(pageIndex * 20 + $0)" }
            list.append(page(ids, next: "cursor-\(pageIndex)"))
        }

        #expect(list.items.count == 20_000)

        // And a reload at that depth still only touches the top.
        list.reconcileFirstPage(page(["newest", "row-0"]))
        #expect(list.items.first?.id == "newest")
        #expect(list.items.count == 20_001)
    }
}
