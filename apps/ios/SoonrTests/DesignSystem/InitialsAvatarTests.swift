import Testing

@testable import Soonr

struct InitialsAvatarTests {
    @Test
    func atwoWordNameGivesTwoInitials() {
        #expect(InitialsAvatar.initials(for: "Vladimir Turkonja") == "VT")
    }

    @Test
    func asingleWordGivesOne() {
        #expect(InitialsAvatar.initials(for: "reader") == "R")
    }

    /// Only the first two, so "Jean Paul Van Damme" is not four letters wide.
    @Test
    func laterWordsAreIgnored() {
        #expect(InitialsAvatar.initials(for: "Ada Grace Byron King") == "AG")
    }

    /// The avatar is shown for accounts that never set a name, where the only
    /// thing to hand is an email.
    @Test
    func anemailUsesItsFirstLetter() {
        #expect(InitialsAvatar.initials(for: "you@example.com") == "Y")
    }

    /// A handle read straight off the profile still leads with a letter: the
    /// at sign is not an initial.
    @Test
    func punctuationIsSkipped() {
        #expect(InitialsAvatar.initials(for: "@reader") == "R")
        #expect(InitialsAvatar.initials(for: "_x_ 99bottles") == "X9")
    }

    @Test
    func nothingToInitialiseFallsBackRatherThanShowingAnEmptyCircle() {
        #expect(InitialsAvatar.initials(for: "") == "?")
        #expect(InitialsAvatar.initials(for: "   ") == "?")
        #expect(InitialsAvatar.initials(for: "🎮") == "?")
    }
}
