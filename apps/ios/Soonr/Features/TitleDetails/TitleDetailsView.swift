import SwiftUI

struct TitleDetailsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(WatchlistStore.self) private var watchlist

    @State private var model: TitleDetailsModel
    @State private var isPresentingSignIn = false
    /// Set when the sheet was raised by the watchlist button, so signing in
    /// finishes the save instead of just dismissing.
    @State private var savesAfterSignIn = false

    init(destination: TitleDestination, dependencies: TitleDetailsDependencies) {
        _model = State(
            initialValue: TitleDetailsModel(
                destination: destination,
                titleDetails: dependencies.titleDetails
            )
        )
    }

    private var isSaved: Bool {
        watchlist.contains(model.destination.id)
    }

    var body: some View {
        TitleDetailsContent(
            state: model.state,
            retry: {
                await model.retry()
            }
        )
        .navigationTitle(model.destination.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                watchlistButton
            }
        }
        .task {
            await model.load()
        }
        // The server is authoritative for this one title, so a load settles
        // what the store believes, including when the list was never fetched.
        .onChange(of: model.serverMembership) { _, membership in
            if let membership {
                watchlist.reconcile(titleID: model.destination.id, isSaved: membership)
            }
        }
        .sheet(isPresented: $isPresentingSignIn, onDismiss: finishSignIn) {
            SignInSheet(prompt: "Sign in to add \(model.destination.name) to your watchlist.")
        }
        .alert(
            "Watchlist unavailable",
            isPresented: Binding(
                get: { watchlist.mutationFailure != nil },
                set: { isPresented in
                    if isPresented == false {
                        watchlist.clearMutationFailure()
                    }
                }
            )
        ) {
            Button("OK") {
                watchlist.clearMutationFailure()
            }
        } message: {
            Text(watchlist.mutationFailure?.message ?? "")
        }
    }

    /// Looks the same signed in or out, so a guest browsing is never nagged;
    /// the tap is what asks them to sign in. Its state comes from the shared
    /// store, so arriving from the watchlist shows a filled bookmark on the
    /// first frame instead of after this screen's own request answers.
    private var watchlistButton: some View {
        Button {
            watchlistTapped()
        } label: {
            Label(
                isSaved ? "In your watchlist" : "Add to watchlist",
                systemImage: isSaved ? "bookmark.fill" : "bookmark"
            )
        }
        // Only meaningful once the title is known to exist.
        .disabled(model.summary == nil)
    }

    private func watchlistTapped() {
        guard session.state.session != nil else {
            savesAfterSignIn = true
            isPresentingSignIn = true
            return
        }

        save(isSaved == false)
    }

    private func finishSignIn() {
        let shouldSave = savesAfterSignIn && session.state.session != nil
        savesAfterSignIn = false
        if shouldSave {
            save(true)
        }
    }

    private func save(_ isSaved: Bool) {
        guard let summary = model.summary else {
            return
        }

        Task {
            await watchlist.setSaved(isSaved, title: summary)
        }
    }
}

private struct TitleDetailsContent: View {
    let state: TitleDetailsState
    let retry: () async -> Void

    var body: some View {
        switch state {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Loading details…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        case let .loaded(details):
            TitleDetailsList(details: details)
        case .notFound:
            ContentUnavailableView(
                "Title not found",
                systemImage: "questionmark.square.dashed",
                description: Text("This game isn't available on Soonr.")
            )
        case let .failed(reason):
            FailureView(title: "Details unavailable", reason: reason) {
                await retry()
            }
        }
    }
}

private struct TitleDetailsList: View {
    let details: TitleDetails

    private var summary: TitleSummary {
        details.summary
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if let description = details.displayDescription {
                Section("About") {
                    Text(description)
                }
            }

            if hasCredits {
                Section("Details") {
                    creditRow("Genres", values: details.genres)
                    creditRow("Developers", values: details.developers)
                    creditRow("Publishers", values: details.publishers)
                }
            }

            if details.releases.isEmpty == false {
                Section("Releases") {
                    ForEach(details.releases, id: \.platformID) { release in
                        LabeledContent(
                            release.platformName,
                            value: ReleaseDateText.format(
                                release.releaseDate,
                                precision: release.precision
                            )
                        )
                    }
                }
            } else if summary.platforms.isEmpty == false {
                Section("Platforms") {
                    ForEach(summary.platforms) { platform in
                        Text(platform.name)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    TitleArtwork(url: summary.coverImageURL, width: .hero, cornerRadius: 16)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(summary.name)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                Label(releaseText, systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Release date: \(releaseText)")
            }
        }
        .padding(.bottom, 4)
    }

    private var releaseText: String {
        ReleaseDateText.format(summary.earliestReleaseDate, precision: .day)
    }

    private var hasCredits: Bool {
        [details.genres, details.developers, details.publishers]
            .contains { $0.isEmpty == false }
    }

    @ViewBuilder
    private func creditRow(_ label: String, values: [String]) -> some View {
        if values.isEmpty == false {
            LabeledContent(label, value: values.joined(separator: ", "))
        }
    }
}

#Preview("Loaded") {
    NavigationStack {
        TitleDetailsView(destination: .preview, dependencies: .preview)
    }
    .environment(SessionStore(authentication: PreviewAuthentication(restored: .preview)))
}

#Preview("Sparse") {
    NavigationStack {
        TitleDetailsView(
            destination: .preview,
            dependencies: .preview(PreviewTitleCatalog(details: .previewSparse))
        )
    }
    .environment(SessionStore(authentication: PreviewAuthentication(restored: .preview)))
}

#Preview("Not found") {
    NavigationStack {
        TitleDetailsView(
            destination: .preview,
            dependencies: .preview(PreviewTitleCatalog(details: nil))
        )
    }
    .environment(SessionStore(authentication: PreviewAuthentication(restored: .preview)))
}

/// A guest, whose watchlist tap opens the sign-in sheet instead of saving.
#Preview("Guest") {
    NavigationStack {
        TitleDetailsView(destination: .preview, dependencies: .preview)
    }
    .environment(SessionStore(authentication: PreviewAuthentication()))
}
