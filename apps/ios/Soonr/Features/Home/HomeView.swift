import SwiftUI

struct HomeView: View {
    @State private var model: HomeModel

    private let details: TitleDetailsDependencies

    init(homeDiscovery: any HomeDiscovering, details: TitleDetailsDependencies) {
        _model = State(initialValue: HomeModel(homeDiscovery: homeDiscovery))
        self.details = details
    }

    var body: some View {
        NavigationStack {
            HomeContent(
                state: model.state,
                retry: {
                    await model.retry()
                },
                refresh: {
                    await model.refresh()
                }
            )
            .navigationTitle("Home")
            .task {
                await model.load()
            }
            .navigationDestination(for: TitleSummary.self) { title in
                TitleDetailsView(summary: title, dependencies: details)
            }
        }
    }
}

private struct HomeContent: View {
    let state: HomeState
    let retry: () async -> Void
    let refresh: () async -> Void

    var body: some View {
        switch state {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Loading discovery…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        case let .loaded(discovery):
            HomeRails(rails: discovery.populatedRails, refresh: refresh)
        case .empty:
            ContentUnavailableView(
                "Nothing to discover yet",
                systemImage: "sparkles",
                description: Text("Soonr has no games to show right now.")
            )
        case let .failed(reason):
            FailureView(title: "Discovery unavailable", reason: reason) {
                await retry()
            }
        }
    }
}

private struct HomeRails: View {
    let rails: [HomeRail]
    let refresh: () async -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(rails) { rail in
                    HomeRailSection(rail: rail)
                }
            }
            .padding(.vertical, 8)
        }
        // Refreshing keeps the current rails on screen, so pulling again does
        // not blank the page the way retry from the failure state does.
        .refreshable {
            await refresh()
        }
    }
}

private struct HomeRailSection: View {
    let rail: HomeRail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(rail.section.title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(rail.titles) { title in
                        NavigationLink(value: title) {
                            TitleCard(title: title)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}

#Preview {
    HomeView(
        homeDiscovery: PreviewTitleCatalog(),
        details: .preview
    )
    .environment(SessionStore(authentication: PreviewAuthentication(restored: .preview)))
}
