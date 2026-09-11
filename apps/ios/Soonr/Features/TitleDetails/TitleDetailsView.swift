import SwiftUI

struct TitleDetailsView: View {
    @State private var model: TitleDetailsModel

    init(summary: TitleSummary, titleDetails: any TitleDetailsLoading) {
        _model = State(
            initialValue: TitleDetailsModel(
                summary: summary,
                titleDetails: titleDetails
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
        .task {
            await model.load()
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
        TitleDetailsView(summary: .preview, titleDetails: PreviewTitleCatalog())
    }
}

#Preview("Sparse") {
    NavigationStack {
        TitleDetailsView(
            summary: .preview,
            titleDetails: PreviewTitleCatalog(details: .previewSparse)
        )
    }
}

#Preview("Not found") {
    NavigationStack {
        TitleDetailsView(
            summary: .preview,
            titleDetails: PreviewTitleCatalog(details: nil)
        )
    }
}
