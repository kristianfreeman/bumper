#if os(macOS)                    // in-process view tests: the Mac's `swift test`
@testable import AppFeatures
import CoreGraphics
import PlaybackCore
import Testing

extension OnScreen {
    /// The player off the TV, on the stand-in backend (UITests/PlayerTests,
    /// iPhoneUITests/PhoneChapterTests and PhonePlayerLayoutTests: the remote,
    /// focus, rotation and real clips stay there). `media-0` is two minutes,
    /// with the mock's chapters: 0:00 "Arrival", 0:30 "The Harbour at
    /// Night", 1:00 unnamed ("Chapter 03"), 1:30 "Landfall".
    @Suite("The player")
    struct Player {
        static let play = ["-autoplay", "media-0"]

        // MARK: The split

        @Test func aTallSpaceSplitsThePlayer() async throws {
            let screen = Screen.player(Self.play, size: Screen.tall)
            try await screen.wait(for: "player.panel")
            try await screen.wait(for: "player.layout") { $0.text == "Full Screen" }
        }

        @Test func aWideSpaceShowsThePictureFullScreen() async throws {
            let screen = Screen.player(Self.play, size: Screen.wide)
            try await screen.wait(for: "player.layout") { $0.text == "Show Details Below" }
            #expect(screen.element("player.panel") == nil)
        }

        @Test func theChoiceOverridesTheShapeEitherWay() async throws {
            let tall = Screen.player(Self.play, size: Screen.tall)
            try await tall.press("player.layout")                            // Full Screen
            try await tall.waitUntilGone("player.panel")
            try await tall.press("player.layout")                            // Show Details Below
            try await tall.wait(for: "player.panel")

            let wide = Screen.player(Self.play, size: Screen.wide)
            try await wide.press("player.layout")
            try await wide.wait(for: "player.panel")
        }

        @Test func theSplitsPictureIsAsWideAsTheSpaceUpToHalfItsHeight() {
            #expect(PlayerSplit.splits(CGSize(width: 390, height: 844), fold: nil))
            #expect(!PlayerSplit.splits(CGSize(width: 1280, height: 720), fold: nil))
            #expect(!PlayerSplit.splits(CGSize(width: 1000, height: 1050), fold: nil))           // nearly square: full screen
            #expect(PlayerSplit(size: CGSize(width: 720, height: 1280), fold: nil, aspect: 16 / 9).pictureHeight == 405)
            #expect(PlayerSplit(size: CGSize(width: 720, height: 1000), fold: nil, aspect: 0.5).pictureHeight == 500)   // a tall picture: half
            // A fold: the picture above it, the panel below it.
            let folded = PlayerSplit(size: CGSize(width: 900, height: 800), fold: CGRect(x: 0, y: 380, width: 900, height: 40), aspect: 16 / 9)
            #expect(folded.pictureHeight == 380 && folded.panelTop == 420)
        }

        // MARK: Chapters

        @Test func thePanelListsTheChaptersByNameWithTheOnePlayingMarked() async throws {
            let screen = Screen.player(Self.play, size: Screen.tall)
            try await screen.wait(forText: "Chapters")
            let chapters = try await screen.wait(forAny: "panel.chapter.")
            #expect(chapters.map(\.id) == (0...3).map { "panel.chapter.\($0)" })
            #expect(chapters[1].text.hasPrefix("The Harbour at Night"))
            #expect(chapters[2].text.hasPrefix("Chapter 3"), "an unnamed chapter reads \(chapters[2].text)")
            #expect(chapters.map(\.value) == ["playing", "", "", ""])
        }

        @Test func aChapterInThePanelGoesThere() async throws {
            let screen = Screen.player(Self.play, size: Screen.tall)
            try await screen.press("panel.chapter.2")
            try await screen.wait(for: "panel.chapter.2") { $0.value == "playing" }
            #expect(screen.engine?.currentTime == .seconds(60))
            #expect(screen.element("panel.chapter.0")?.value == "")
        }

        @Test func wideTheChaptersMenuNamesTheOnePlaying() async throws {
            let screen = Screen.player(Self.play, size: Screen.wide)
            try await screen.wait(for: "control.chapters") { $0.text == "Arrival" }
            screen.engine?.currentTime = .seconds(95)
            try await screen.wait(for: "control.chapters") { $0.text == "Landfall" }
        }

        // MARK: Starting

        @Test func aSlowStartSaysWhereItsGoingAfterASecond() async throws {
            let start = ContinuousClock.now
            let screen = Screen.player(Self.play + ["-startAt", "42"], size: Screen.wide)
            screen.nextEngine = { $0.holdsLoading = true }
            try await screen.waitUntil("the backend to be opening") { screen.engine?.status == .loading }
            #expect(screen.element("player.startMessage") == nil, "words before a second had passed")
            try await screen.wait(for: "player.startMessage", timeout: .seconds(2)) { $0.text == "Getting to 0:42…" }
            #expect(ContinuousClock.now - start >= .seconds(1))
            screen.engine?.finishLoading()
            #expect(screen.element("player.startMessage") != nil, "gone before the picture moved")
            // The picture moves (and keeps moving, as a real one does): the start is over.
            try await screen.waitUntil("the words to go once it moves") {
                screen.engine?.currentTime += .milliseconds(20)
                return screen.element("player.startMessage") == nil
            }
        }

        @Test func untrackedFromAPagePlaysSayingSo() async throws {
            let screen = Screen(route: "item:movie-0001")
            try await screen.press("detail.background")
            try await screen.wait(for: "player.backgroundTag")
            #expect(screen.app.playback?.background == true)
        }

        // MARK: Picture in Picture

        @Test func thePiPButtonShowsOnlyWhileTheBackendCanFloat() async throws {
            let screen = Screen.player(Self.play, size: Screen.wide)
            try await screen.wait(for: "player.playPause")
            #expect(screen.element("player.pip") == nil)
            screen.engine?.pictureInPicture?.setPossible(true)
            try await screen.wait(for: "player.pip")
            screen.engine?.pictureInPicture?.setPossible(false)
            try await screen.waitUntilGone("player.pip")
        }

        @Test func aBackendThatCantFloatHasNoPiPButton() async throws {
            let screen = Screen.player(Self.play, size: Screen.tall)
            screen.nextEngine = { $0.pictureInPicture = nil }
            try await screen.wait(for: "player.playPause")
            try await screen.settle()
            #expect(screen.element("player.pip") == nil)
        }

        @Test func pipFloatsThePictureAndClosesTheScreenThenComesBack() async throws {
            let screen = Screen.player(Self.play, size: Screen.wide)
            try await screen.wait(for: "player.playPause")
            let pip = try #require(screen.engine?.pictureInPicture)
            pip.setPossible(true)
            try await screen.press("player.pip")
            try await screen.waitUntilGone("player.surface")
            #expect(screen.app.playback == nil && screen.app.floatingPlayer != nil, "the screen should close with it playing on")
            #expect(screen.engine?.status == .playing)
            await pip.restore()                                              // the floating window's restore button
            try await screen.wait(for: "player.surface")
            #expect(screen.engines.count == 1, "it should come back to the same playback, not start again")
        }
    }
}
#endif
