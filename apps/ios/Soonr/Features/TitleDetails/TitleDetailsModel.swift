import Foundation
import Observation

enum TitleDetailsState: Equatable {
    case loading
    case loaded(TitleDetails)
    case notFound
    case failed(message: String)
}

@MainActor
@Observable
final class TitleDetailsModel {
    let summary: TitleSummary
    private(set) var state: TitleDetailsState = .loading

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
            let details = try await titleDetails.titleDetails(id: summary.id)
            try Task.checkCancellation()
            state = details.map(TitleDetailsState.loaded) ?? .notFound
        } catch is CancellationError {
            return
        } catch {
            state = .failed(
                message: error.localizedDescription.isEmpty
                    ? "Details couldn't be loaded. Please try again."
                    : error.localizedDescription
            )
        }
    }
}
