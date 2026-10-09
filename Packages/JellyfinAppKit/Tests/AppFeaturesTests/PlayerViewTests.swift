#if os(macOS)                    // in-process view tests: the Mac's `swift test`
@testable import AppFeatures
import AppCore
import CoreGraphics
import JellyfinAPI
import JellyfinMocks
import PlaybackCore
import Synchronization
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
            try await screen.wait(for: "player.layout") { $0.text == "Show Details Beside" }
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
            #expect(!PlayerSplit.canSplit(CGSize(width: 852, height: 372), fold: nil), "a phone on its side offers no split")
            #expect(PlayerSplit.canSplit(CGSize(width: 1180, height: 780), fold: nil), "an iPad on its side can")
            #expect(!PlayerSplit.splits(CGSize(width: 1000, height: 1050), fold: nil))           // nearly square: full screen
            #expect(PlayerSplit(size: CGSize(width: 720, height: 1280), fold: nil, aspect: 16 / 9).pictureHeight == 405)
            #expect(PlayerSplit(size: CGSize(width: 720, height: 1000), fold: nil, aspect: 0.5).pictureHeight == 500)   // a tall picture: half
            // A fold: the picture above it, the panel below it.
            let folded = PlayerSplit(size: CGSize(width: 900, height: 800), fold: CGRect(x: 0, y: 380, width: 900, height: 40), aspect: 16 / 9)
            #expect(folded.pictureHeight == 380 && folded.panelTop == 420)
            // Split by choice in a wide space: side by side, the panel down the right.
            let side = PlayerSplit(size: CGSize(width: 1180, height: 780), fold: nil, aspect: 16 / 9)
            #expect(side.isSideBySide && side.pictureWidth == 802 && side.pictureHeight == 451)
            #expect(!PlayerSplit(size: CGSize(width: 720, height: 1280), fold: nil, aspect: 16 / 9).isSideBySide)
        }

        // MARK: Up Next

        /// The mock's first show, its second episode (the show has seven).
        static let episode = ["-autoplay", "series-000-s1-e2", "-quickTimers"]

        @Test func upNextIsTheNextEpisodeAndAddingPutsItAfter() async throws {
            let screen = Screen.player(Self.episode, size: Screen.tall)
            let player = try await screen.playerController()
            try await screen.wait(for: "upnext.series-000-s1-e3")
            try await screen.waitUntil("films like it") { !player.similarItems.isEmpty }
            let film = player.similarItems[0]
            player.addToUpNext(film)
            try await screen.wait(for: "upnext.\(film.id)")
            #expect(player.upNextList.map(\.id).prefix(2) == ["series-000-s1-e3", film.id])
            #expect(screen.app.queue.plan.entries.prefix(3).map(\.id) == ["series-000-s1-e2", "series-000-s1-e3", film.id],
                    "this one, what was next, then the new one")
        }

        /// The TV's Up Next card and the phone remote: only what you've lined
        /// up — nothing for the next episode that plays by itself.
        @Test func onlyWhatYouLinedUpIsChosen() async throws {
            let screen = Screen.player(Self.episode, size: Screen.tall)
            let player = try await screen.playerController()
            try await screen.waitUntil("films like it") { !player.similarItems.isEmpty && player.nextEpisode != nil }
            #expect(player.chosenUpNext.isEmpty, "the next episode plays by itself: nothing chosen")
            let film = player.similarItems[0]
            player.addToUpNext(film)
            #expect(player.chosenUpNext.map(\.id) == ["series-000-s1-e3", film.id])
        }

        @Test func addToUpNextOffersTheRestOfTheShowFirstAndTakesItBackOut() async throws {
            let screen = Screen.player(Self.episode, size: Screen.tall)
            let player = try await screen.playerController()
            try await screen.wait(for: "upnext.add")
            try await screen.waitUntil("the rest of the show") { player.addSections.first?.items.isEmpty == false }
            let more = try #require(player.addSections.first)
            #expect(more.title.hasPrefix("More from "))
            #expect(more.items.first?.id == "series-000-s1-e4", "the next episode plays by itself, so it isn't offered")
            player.toggleUpNext(more.items[0])
            #expect(player.isUpNext("series-000-s1-e4"))
            player.toggleUpNext(more.items[0])
            #expect(!player.isUpNext("series-000-s1-e4"))
            #expect(player.isUpNext("series-000-s1-e3"), "the next episode stays")
        }

        @Test func thePanelHasNoChaptersNow() async throws {
            let screen = Screen.player(Self.play, size: Screen.tall)
            try await screen.wait(for: "upnext.add")
            #expect(screen.text("Chapters") == nil)
        }

        // MARK: The end card

        @Test func atTheEndKeepGoingCountsDownThenPlaysTheNextEpisode() async throws {
            let screen = Screen.player(Self.episode, size: Screen.wide)
            let player = try await screen.playerController()
            try await screen.waitUntil("the next episode") { player.nextEpisode != nil }
            screen.engine?.reachEnd()
            try await screen.wait(for: "option.end-next") { $0.text.contains("Keep going") }
            #expect(screen.element("option.end-done") != nil)
            try await screen.waitUntil("the next episode to play", timeout: .seconds(4)) { screen.app.playback?.item.id == "series-000-s1-e3" }
        }

        @Test func movingTheRemoteStopsTheCountdown() async throws {
            let screen = Screen.player(Self.episode, size: Screen.wide)
            let player = try await screen.playerController()
            try await screen.waitUntil("the next episode") { player.nextEpisode != nil }
            screen.engine?.reachEnd()
            try await screen.wait(for: "option.end-next") { $0.text.contains("Keep going · in ") }
            player.holdCountdown()
            try await screen.wait(for: "option.end-next") { !$0.text.contains("Keep going · in ") }
            try await Task.sleep(for: .seconds(2))                     // past the quick countdown
            #expect(screen.app.playback?.item.id == "series-000-s1-e2", "it went on by itself")
            #expect(player.endCard?.held == true)
        }

        @Test func doneForTonightClosesThePlayer() async throws {
            let screen = Screen.player(Self.episode, size: Screen.wide)
            let player = try await screen.playerController()
            try await screen.waitUntil("the next episode") { player.nextEpisode != nil }
            screen.engine?.reachEnd()
            try await screen.press("option.end-done")
            try await screen.waitUntil("the player to close") { screen.app.playback == nil }
        }

        @Test func somethingDifferentPlaysAFilmLikeIt() async throws {
            let screen = Screen.player(Self.episode, size: Screen.wide)
            let player = try await screen.playerController()
            try await screen.waitUntil("films like it") { !player.similarItems.isEmpty && player.nextEpisode != nil }
            let instead = try #require(player.somethingDifferent)
            screen.engine?.reachEnd()
            try await screen.press("option.end-instead")
            try await screen.waitUntil("it to play") { screen.app.playback?.item.id == instead.id }
        }

        @Test func withTheSleepTimerAtTheEndOfThisThereIsNoCard() async throws {
            let screen = Screen.player(Self.episode, size: Screen.wide)
            let player = try await screen.playerController()
            try await screen.waitUntil("the next episode") { player.nextEpisode != nil }
            screen.app.sleepTimer.set(.endOfItem)
            screen.engine?.reachEnd()
            try await screen.waitUntil("the player to close") { screen.app.playback == nil }
            #expect(player.endCard == nil)
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

        // MARK: Low memory (VLCKit's ASS)

        /// The typeset clip, with a threshold no device has: the memory
        /// guard trips at its first reading (`-memoryGuardAt`, as on a device).
        static let lowMemory = ["-autoplay", "media-1", "-memoryGuardAt", "100000"]

        @Test func lowMemorySwapsVLCKitsASSForThePlainWordsAndSaysSo() async throws {
            let screen = Screen.player(Self.lowMemory, size: Screen.wide)
            try await screen.wait(for: "player.notice") { $0.text == "Simpler subtitles, so playback keeps going" }
            let engine = try #require(screen.engine)
            #expect(engine.kind == .vlc)
            #expect(engine.subtitleRequests.first??.codec == "ass", "VLCKit should have drawn the ASS first")
            #expect(engine.subtitleRequests.last.map { $0 == nil } == true, "VLCKit's track should be off")
            #expect(engine.activeSubtitleTrack == nil)
            #expect(engine.status == .playing, "playback should carry on")
            engine.currentTime = .seconds(1)
            try await screen.wait(for: "subtitle.text") { $0.text == "Plain words, no typesetting." }
            try await screen.wait(for: "player.subtitles") { $0.text == "WebVTT" }
        }

        /// As a real MKV did: subtitles set to off here, VLCKit turns the
        /// file's default ASS on by itself — and that one's watched too.
        @Test func lowMemoryCatchesTheASSVLCKitTurnedOnByItself() async throws {
            let screen = Screen.player(Self.lowMemory, size: Screen.wide)
            screen.app.settings.subtitleMode = .off
            screen.nextEngine = { $0.picksItsOwnSubtitle = true }
            try await screen.wait(for: "player.notice") { $0.text == "Simpler subtitles, so playback keeps going" }
            let engine = try #require(screen.engine)
            #expect(engine.subtitleRequests.first.map { $0 == nil } == true, "the app should have asked for none: VLCKit picked it")
            #expect(engine.drawnSubtitleStream == nil, "VLCKit's track should be off")
            engine.currentTime = .seconds(1)
            try await screen.wait(for: "subtitle.text") { $0.text == "Plain words, no typesetting." }
        }

        @Test func lowMemoryWithNoWebVTTTurnsSubtitlesOffSayingSo() async throws {
            MockMedia.webVTTFails.withLock { $0 = true }
            defer { MockMedia.webVTTFails.withLock { $0 = false } }
            let screen = Screen.player(Self.lowMemory, size: Screen.wide)
            try await screen.wait(for: "player.notice") { $0.text == "Subtitles off, so playback keeps going" }
            screen.engine?.currentTime = .seconds(1)
            try await screen.settle()
            #expect(screen.element("subtitle.text") == nil)
            #expect(screen.engine?.activeSubtitleTrack == nil)
            #expect(screen.element("player.subtitles")?.text == "off")
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
