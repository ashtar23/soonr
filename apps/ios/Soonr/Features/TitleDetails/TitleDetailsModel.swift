import Foundation
import Observation

enum TitleDetailsState: Equatable {
    case loading
    case loaded(TitleDetails)
    case notFound
    case failed(FailureReason)

    var details: TitleDetails? {
        if case let .loaded(details) = self {
            return details
        }

        return nil
    }
}

@MainActor
@Observable
final class TitleDetailsModel {
    let destination: TitleDestination
    private(set) var state: TitleDetailsState = .loading
    /// Authoritative for this one title even when the list is stale or was
    /// never loaded. `nil` until a load succeeds.
    private(set) var serverMembership: Bool?

    @ObservationIgnored private let titleDetails: any TitleDetailsLoading

    init(destination: TitleDestination, titleDetails: any TitleDetailsLoading) {
        self.destination = destination
        self.titleDetails = titleDetails
    }

    /// Known only once the server answers. The watchlist needs it to show a
    /// row for a game the list has never seen, so saving waits for a load.
    var summary: TitleSummary? {
        state.details?.summary
    }

    /// Ignores repeated calls after a successful load, so returning to the
    /// screen does not refetch.
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
            let result = try await titleDetails.titleDetails(id: destination.id)
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
