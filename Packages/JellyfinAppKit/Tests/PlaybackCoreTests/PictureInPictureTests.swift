@testable import PlaybackCore
import Testing

/// Picture in Picture: when the player's screen closes and comes back, and
/// when floating ends playback.
@Suite("Picture in Picture")
@MainActor
struct PictureInPictureTests {
    /// The PiP button closes the screen once the picture floats; restoring
    /// brings it back, and the stop after a restore ends nothing.
    @Test func buttonClosesTheScreenAndRestoreReopensIt() {
        var flow = PictureInPictureFlow()
        flow.ask()
        #expect(flow.started() == .closeScreen)
        #expect(flow.screenClosed)
        #expect(flow.restore() == .reopenScreen)
        #expect(!flow.screenClosed)
        #expect(flow.stopped() == .none)
    }

    /// Closing the window with the screen gone ends playback.
    @Test func closingTheWindowWithTheScreenClosedEndsPlayback() {
        var flow = PictureInPictureFlow()
        flow.ask()
        _ = flow.started()
        #expect(flow.stopped() == .endPlayback)
        #expect(!flow.screenClosed)
    }

    /// Leaving the app floats it on its own: the screen stays for your
    /// return, and neither a restore nor a close touches it.
    @Test func floatingOnItsOwnKeepsTheScreen() {
        var flow = PictureInPictureFlow()
        #expect(flow.started() == .none)
        #expect(flow.restore() == .none)
        #expect(flow.stopped() == .none)
        _ = flow.started()
        #expect(flow.stopped() == .none)
    }

    /// A press that never floated (it failed to start) doesn't close the
    /// screen the next time it floats on its own.
    @Test func aFailedStartForgetsThePress() {
        var flow = PictureInPictureFlow()
        flow.ask()
        #expect(flow.stopped() == .none)
        #expect(flow.started() == .none)
    }

    /// The backend's reports reach the player, in order, and keep the state.
    @Test func backendReportsReachThePlayer() async {
        var calls: [String] = []
        let pip = PictureInPicture(start: { calls.append("start") }, stop: { calls.append("stop") })
        pip.didStart = { calls.append("didStart") }
        pip.restoreScreen = { calls.append("restore") }
        pip.didStop = { calls.append("didStop") }
        pip.setPossible(true)
        pip.start()
        pip.started()
        #expect(pip.isPossible && pip.isActive)
        await pip.restore()
        pip.stopped()
        #expect(!pip.isActive)
        #expect(calls == ["start", "didStart", "restore", "didStop"])
    }
}
