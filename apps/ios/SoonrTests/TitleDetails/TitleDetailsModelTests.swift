import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite(.tags(.networking))
struct TitleDetailsModelTests {
    @Test
    func successfulLoadShowsDetailsForTheSelectedTitle() async {
        let loader = RecordingTitleDetails(results: [.success(.preview)])
        let model = TitleDetailsModel(summary: .preview, titleDetails: loader)

        await model.load()

        #expect(model.state == .loaded(.preview))
        #expect(await loader.requestedIDs == [TitleSummary.preview.id])
    }

    @Test
    func missingTitleShowsNotFound() async {
        let model = TitleDetailsModel(
            summary: .preview,
            titleDetails: RecordingTitleDetails(results: [.success(nil)])
        )

        await model.load()

        #expect(model.state == .notFound)
    }

    @Test
    func failureShowsItsMessageAndRetryRecovers() async {
        let loader = RecordingTitleDetails(results: [
            .failure(DetailsFixtureError.offline),
            .success(.preview),
        ])
        let model = TitleDetailsModel(summary: .preview, titleDetails: loader)

        await model.load()
        #expect(model.state == .failed(.unknown(message: "You're offline.")))

        await model.retry()
        #expect(model.state == .loaded(.preview))
        #expect(await loader.requestedIDs.count == 2)
    }

    @Test
    func loadRecordsWhatTheServerSaysAboutMembership() async {
        let model = TitleDetailsModel(
            summary: .preview,
            titleDetails: RecordingTitleDetails(results: [.success(.saved)])
        )

        await model.load()

        #expect(model.state == .loaded(.preview))
        #expect(model.serverMembership == true)
    }

    @Test
    func aTitleThatIsNotSavedReportsSoFromTheServer() async {
        let model = TitleDetailsModel(
            summary: .preview,
            titleDetails: RecordingTitleDetails(results: [.success(.preview)])
        )

        await model.load()

        #expect(model.serverMembership == false)
    }

    @Test
    func loadingAgainAfterSuccessDoesNotRefetch() async {
        let loader = RecordingTitleDetails(results: [.success(.preview)])
        let model = TitleDetailsModel(summary: .preview, titleDetails: loader)

        await model.load()
        await model.load()

        #expect(model.state == .loaded(.preview))
        #expect(await loader.requestedIDs.count == 1)
    }
}

private actor RecordingTitleDetails: TitleDetailsLoading {
    private(set) var requestedIDs: [String] = []
    private var results: [Result<TitleDetailsResult?, DetailsFixtureError>]

    init(results: [Result<TitleDetailsResult?, DetailsFixtureError>]) {
        self.results = results
    }

    func titleDetails(id: String) async throws -> TitleDetailsResult? {
        requestedIDs.append(id)
        return try results.removeFirst().get()
    }
}

private extension TitleDetailsResult {
    static let preview = TitleDetailsResult(details: .preview, isInWatchlist: false)
    static let saved = TitleDetailsResult(details: .preview, isInWatchlist: true)
}

private enum DetailsFixtureError: Error, LocalizedError, Sendable {
    case offline

    var errorDescription: String? {
        "You're offline."
    }
}
