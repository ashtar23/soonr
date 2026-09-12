import Foundation
import Observation

enum HomeState: Equatable {
    case loading
    case loaded(HomeDiscovery)
    case empty
    case failed(message: String)
}

@MainActor
@Observable
final class HomeModel {
    private(set) var state: HomeState = .loading

    @ObservationIgnored private let homeDiscovery: any HomeDiscovering

    init(homeDiscovery: any HomeDiscovering) {
        self.homeDiscovery = homeDiscovery
    }

    /// Loads once; returning to the tab keeps what is already on screen.
    func load() async {
        if case .loaded = state {
            return
        }

        await fetch(showingLoadingState: true)
    }

    func retry() async {
        await fetch(showingLoadingState: true)
    }

    /// Pull to refresh keeps the current rails visible while reloading.
    func refresh() async {
        await fetch(showingLoadingState: false)
    }

    private func fetch(showingLoadingState: Bool) async {
        if showingLoadingState {
            state = .loading
        }

        do {
            let discovery = try await homeDiscovery.homeDiscovery()
            try Task.checkCancellation()
            state = discovery.isEmpty ? .empty : .loaded(discovery)
        } catch is CancellationError {
            return
        } catch {
            state = .failed(
                message: error.localizedDescription.isEmpty
                    ? "Discovery couldn't be loaded. Please try again."
                    : error.localizedDescription
            )
        }
    }
}
