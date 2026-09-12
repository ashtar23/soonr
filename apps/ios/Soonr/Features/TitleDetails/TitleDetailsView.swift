import SwiftUI

struct TitleDetailsView: View {
    @Environment(SessionStore.self) private var session

    @State private var model: TitleDetailsModel
    @State private var isPresentingSignIn = false
    /// Set when the sheet was raised by the watchlist button, so signing in
    /// finishes the save instead of just dismissing.
    @State private var savesAfterSignIn = false

    init(summary: TitleSummary, dependencies: TitleDetailsDependencies) {
        _model = State(
            initialValue: TitleDetailsModel(
                summary: summary,
                titleDetails: dependencies.titleDetails,
                watchlist: dependencies.watchlist
            )
        )
    }

    var body: some View {
        TitleDetailsContent(
            state: model.state,
            retry: {
                await model.retry()
            }
        )
        .navigationTitle(model.summary.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                watchlistButton
            }
        }
        .task {
            await model.load()
        }
        .sheet(isPresented: $isPresentingSignIn, onDismiss: finishSignIn) {
            SignInSheet(prompt: "Sign in to add \(model.summary.name) to your watchlist.")
        }
        .alert(
            "Watchlist unavailable",
            isPresented: Binding(
                get: { model.watchlistFailure != nil },
                set: { isPresented in
                    if isPresented == false {
                        model.clearWatchlistFailure()
                    }
                }
            )
        ) {
            Button("OK") {
                model.clearWatchlistFailure()
            }
        } message: {
            Text(model.watchlistFailure ?? "")
        }
    }

    /// Looks the same signed in or out, so a guest browsing is never nagged;
    /// the tap is what asks them to sign in.
    private var watchlistButton: some View {
        Button {
            watchlistTapped()
        } label: {
            Label(
                model.isInWatchlist ? "In your watchlist" : "Add to watchlist",
                systemImage: model.isInWatchlist ? "bookmark.fill" : "bookmark"
            )
        }
        // Only meaningful once the title is known to exist.
        .disabled(model.state.isLoaded == false)
    }

    private func watchlistTapped() {
        guard session.state.session != nil else {
            savesAfterSignIn = true
            isPresentingSignIn = true
            return
        }

        Task {
            await model.toggleWatchlist()
        }
    }

    private func finishSignIn() {
        let shouldSave = savesAfterSignIn && session.state.session != nil
        savesAfterSignIn = false
        guard shouldSave else {
            return
        }

        Task {
            await model.setInWatchlist(true)
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
        case let .failed(message):
            ContentUnavailableView {
                Label("Details unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", systemImage: "arrow.clockwise") {
                    Task {
                        await retry()
                    }
                }
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
        TitleDetailsView(summary: .preview, dependencies: .preview)
    }
    .environment(SessionStore(authentication: PreviewAuthentication(restored: .preview)))
}

#Preview("Sparse") {
    NavigationStack {
        TitleDetailsView(
            summary: .preview,
            dependencies: .preview(PreviewTitleCatalog(details: .previewSparse))
        )
    }
    .environment(SessionStore(authentication: PreviewAuthentication(restored: .preview)))
}

#Preview("Not found") {
    NavigationStack {
        TitleDetailsView(
            summary: .preview,
            dependencies: .preview(PreviewTitleCatalog(details: nil))
        )
    }
    .environment(SessionStore(authentication: PreviewAuthentication(restored: .preview)))
}

/// A guest, whose watchlist tap opens the sign-in sheet instead of saving.
#Preview("Guest") {
    NavigationStack {
        TitleDetailsView(summary: .preview, dependencies: .preview)
    }
    .environment(SessionStore(authentication: PreviewAuthentication()))
}
