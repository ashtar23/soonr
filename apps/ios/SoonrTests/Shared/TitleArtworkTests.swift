import Foundation
import Testing
@testable import Soonr

struct TitleArtworkTests {
    @Test(arguments: [
        (
            "https://media.rawg.io/media/games/1f4/1f47a270b8f241e4676b14d39ec620f7.jpg",
            TitleArtwork.Width.thumbnail,
            "https://media.rawg.io/media/resize/420/-/games/1f4/1f47a270b8f241e4676b14d39ec620f7.jpg"
        ),
        (
            "https://media.rawg.io/media/screenshots/2dc/2dcc5b76de63a99799364f962334525f.jpg",
            .hero,
            "https://media.rawg.io/media/resize/1280/-/screenshots/2dc/2dcc5b76de63a99799364f962334525f.jpg"
        ),
    ])
    func rawgMediaRequestsAResizedCopy(original: String, width: TitleArtwork.Width, expected: String) throws {
        let url = try #require(URL(string: original))

        #expect(TitleArtwork.sizedURL(url, width: width).absoluteString == expected)
    }

    @Test(arguments: [
        "https://media.rawg.io/media/resize/640/-/games/1f4/cover.jpg",
        "https://media.rawg.io/media/crop/600/400/games/1f4/cover.jpg",
        "https://images.example.com/media/games/1f4/cover.jpg",
        "https://media.rawg.io/other/games/1f4/cover.jpg",
    ])
    func otherURLsAreUnchanged(original: String) throws {
        let url = try #require(URL(string: original))

        #expect(TitleArtwork.sizedURL(url, width: .thumbnail) == url)
    }
}
