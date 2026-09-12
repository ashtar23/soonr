import Foundation
import Observation

enum TitleDetailsState: Equatable {
    case loading
    case loaded(TitleDetails)
    case notFound
    case failed(FailureReason)

    var isLoaded: Bool {
        if case .loaded = self {
            return true
        }

        return false
    }
}

@MainActor
@Observable
final class TitleDetailsModel {
    let summary: TitleSummary
    private(set) var state: TitleDetailsState = .loading
    /// What the server says about this title, which is authoritative even when
    /// the watchlist list itself is stale or was never loaded. `nil` until a
    /// load succeeds. The button reads the shared store instead, so the tab and
    /// this screen cannot disagree.
    private(set) var serverMembership: Bool?

    @ObservationIgnored private let titleDetails: any TitleDetailsLoading

    init(summary: TitleSummary, titleDetails: any TitleDetailsLoading) {
        self.summary = summary
        self.titleDetails = titleDetails
    }

    /// Loads details once; repeated calls after a successful load are ignored
    /// so returning to the screen does not refetch.
    func load() async {
        if case .loaded = state {
            return
        }

        await fetch()
    }

    func retry() async {
        await fetch()
    }

    private func fetch() async {
        state = .loading

        do {
            let result = try await titleDetails.titleDetails(id: summary.id)
            try Task.checkCancellation()
            serverMembership = result?.isInWatchlist
            state = result.map { .loaded($0.details) } ?? .notFound
        } catch is CancellationError {
            return
        } catch {
            state = .failed(FailureReason(error))
        }
    }
}
