import Foundation
@testable import PlaybackCore
import Testing

/// The remote's behaviour in the player: where the head goes, and exactly
/// where playback resumes.
@Suite("Remote transport")
@MainActor
struct TransportModelTests {
    final class FakePlayer: TransportTarget {
        var position: Duration = .seconds(600)
        var length: Duration = .seconds(3600)
        var isPlaying = true
        var seeks: [Duration] = []
        var skips: [Duration] = []
        func play() { isPlaying = true }
        func pause() { isPlaying = false }
        func seek(to time: Duration) async { seeks.append(time); position = time }
        func skip(by delta: Duration) async { skips.append(delta); position += delta }
    }

    func make() -> (TransportModel, FakePlayer) {
        let model = TransportModel(), player = FakePlayer()
        model.target = player
        return (model, player)
    }

    /// Swipe while playing → paused, scrubbing; lifting the finger leaves the
    /// head where it is; Select plays from exactly there.
    @Test func swipeScrubsAndSelectResumesAtTheHead() async throws {
        let (model, player) = make()
        model.panBegan()
        model.panChanged(dx: 0.03, speed: 0.5)                 // a wobble: nothing yet
        #expect(model.head == nil && player.isPlaying)
        for _ in 0..<10 { model.panChanged(dx: 0.03, speed: 0.5) }
        #expect(!player.isPlaying)
        let head = try #require(model.head)
        #expect(head > .seconds(600))
        model.panEnded()
        #expect(model.head == head, "Lifting the finger moved the head")

        model.togglePlayPause(source: "select")
        #expect(model.head == nil)
        try await Task.sleep(for: .milliseconds(20))
        #expect(player.seeks == [head], "Resumed somewhere other than the head")
        #expect(player.isPlaying)
    }

    /// Clicks skip while playing and step the head while paused; Menu puts
    /// everything back; a doubled Play/Pause press counts once.
    @Test func clicksMenuAndDuplicatePresses() async throws {
        let (model, player) = make()
        model.click(.forward)
        try await Task.sleep(for: .milliseconds(20))
        #expect(player.skips == [.seconds(10)] && model.head == nil)

        model.togglePlayPause(source: "select")                // pause
        model.togglePlayPause(source: "NowPlaying")            // same press, delivered twice
        #expect(!player.isPlaying)
        model.click(.backward)
        model.click(.backward)
        #expect(model.head == player.position - .seconds(20))
        #expect(model.cancel())
        #expect(model.head == nil && !player.isPlaying, "Cancel resumed a video that was paused")
        #expect(!model.cancel())
    }

    /// Holding scans faster the longer it's held, and stops at the end.
    @Test func holdScansAndClamps() {
        let (model, player) = make()
        player.position = .seconds(3500)
        model.holdBegan(.forward)
        model.tick(.seconds(1))
        #expect(model.head == .seconds(3520))
        for _ in 0..<10 { model.tick(.seconds(1)) }
        #expect(model.head == .seconds(3599))                  // length − 1 s
        model.holdEnded()
        #expect(model.scanning == nil && model.head == .seconds(3599))
    }
}
