import Foundation
public import Observation

/// What the remote controls: the player, as the transport sees it.
@MainActor
public protocol TransportTarget: AnyObject {
    /// Where playback is (or is heading, mid-seek).
    var position: Duration { get }
    var length: Duration { get }
    var isPlaying: Bool { get }
    func play()
    func pause()
    func seek(to time: Duration) async
    func skip(by delta: Duration) async
}

/// The player's remote-control behaviour, as one state machine — the same
/// model as Apple's own player, so it works the way Apple TV users expect:
///
/// | Input              | Playing                     | Paused / scrubbing               |
/// |--------------------|-----------------------------|----------------------------------|
/// | Select, Play/Pause | pause                       | play (from the scrub head)       |
/// | Swipe left/right   | pause and scrub             | move the head with the finger    |
/// | Click left/right   | skip ±10 s                  | head ±10 s                       |
/// | Hold left/right    | scan (accelerating)         | scan (accelerating)              |
/// | Menu               | —                           | cancel: back to where it was     |
///
/// The head only moves while a finger, a click or a hold moves it: lifting
/// the finger leaves it exactly where it is, and Select seeks exactly there.
@MainActor
@Observable
public final class TransportModel {
    public enum Direction: Sendable { case backward, forward }

    /// A short-lived glyph confirming an action.
    public struct Feedback: Equatable, Sendable {
        public enum Kind: Sendable { case play, pause, skipBack, skipForward }
        public let kind: Kind
        public let id: Int
    }

    /// The scrub head (nil when not scrubbing).
    public private(set) var head: Duration?
    public private(set) var feedback: Feedback?
    /// Scanning (a held left/right), and which way.
    public private(set) var scanning: Direction?
    public var isScrubbing: Bool { head != nil }

    @ObservationIgnored public weak var target: (any TransportTarget)?
    /// Something moved the head, paused, skipped…: keep the controls up.
    @ObservationIgnored public var onActivity: (() -> Void)?
    /// Diagnostics (the trace log).
    @ObservationIgnored public var log: ((String) -> Void)?

    @ObservationIgnored private var origin: Duration = .zero
    @ObservationIgnored private var resumeOnCancel = false
    @ObservationIgnored private var panTravel: Double = 0
    @ObservationIgnored private var panStartedScrub = false
    @ObservationIgnored private var lastToggle: ContinuousClock.Instant?
    @ObservationIgnored private var scanHeld: Duration = .zero
    @ObservationIgnored private var feedbackCount = 0

    public init() {}

    // MARK: Buttons

    /// Select (centre click) and the Play/Pause button.
    public func togglePlayPause(source: String) {
        // One press can arrive twice (the press itself and Now Playing's
        // command): a second toggle inside 350 ms is the same press.
        if let last = lastToggle, last.duration(to: .now) < .milliseconds(350) {
            log?("input \(source): duplicate ignored")
            return
        }
        lastToggle = .now
        guard let target else { return }
        if let head {
            log?("input \(source): play from scrub head \(head.clock)")
            commit(head)
        } else if target.isPlaying {
            log?("input \(source): pause at \(target.position.clock)")
            target.pause()
            show(.pause)
        } else {
            log?("input \(source): play")
            target.play()
            show(.play)
        }
        onActivity?()
    }

    /// A click on the left or right of the clickpad (not a swipe).
    public func click(_ direction: Direction) {
        guard let target else { return }
        let step: Duration = direction == .forward ? .seconds(10) : .seconds(-10)
        if isScrubbing || !target.isPlaying {
            beginScrubIfNeeded()
            move(to: (head ?? target.position) + step)
            log?("input click \(direction): head \(head?.clock ?? "-")")
        } else {
            Task { await target.skip(by: step) }
            show(direction == .forward ? .skipForward : .skipBack)
            log?("input click \(direction): skip")
        }
        onActivity?()
    }

    // MARK: Touch surface

    public func panBegan() {
        panTravel = 0
        panStartedScrub = false
    }

    /// `dx`: horizontal movement since the last call, in touch-surface widths
    /// (one full swipe across the pad ≈ 1). `speed`: pad widths per second.
    public func panChanged(dx: Double, speed: Double) {
        guard let target else { return }
        panTravel += dx
        if !isScrubbing {
            // While playing, a swipe has to mean it before it pauses the video
            // (a resting thumb or a click's wobble doesn't).
            guard abs(panTravel) > 0.08 else { return }
            beginScrubIfNeeded()
            panStartedScrub = true
            move(to: target.position + seconds(forPad: panTravel, speed: speed))
            return
        }
        move(to: (head ?? target.position) + seconds(forPad: dx, speed: speed))
        onActivity?()
    }

    /// The finger lifted: the head stays exactly where it is.
    public func panEnded() {
        if isScrubbing {
            log?("input swipe: \(String(format: "%.2f", panTravel)) pad → head \(head?.clock ?? "-")")
        }
        panTravel = 0
    }

    // MARK: Hold to scan

    public func holdBegan(_ direction: Direction) {
        beginScrubIfNeeded()
        scanning = direction
        scanHeld = .zero
        log?("input hold \(direction): scan")
        onActivity?()
    }

    public func holdEnded() {
        guard scanning != nil else { return }
        scanning = nil
        log?("input hold end: head \(head?.clock ?? "-")")
    }

    /// Advance a scan by `dt` (the view's display timer drives this). The head
    /// speeds up the longer the button is held: 20 → 60 → 180 s per second.
    public func tick(_ dt: Duration) {
        guard let scanning, let current = head else { return }
        scanHeld += dt
        let rate: Double = scanHeld < .milliseconds(1500) ? 20 : scanHeld < .seconds(3) ? 60 : 180
        let delta = Duration.seconds(rate * dt.secondsValue)
        move(to: scanning == .forward ? current + delta : current - delta)
        onActivity?()
    }

    // MARK: Menu

    /// Menu/Back: cancels a scrub (back to where it was). Returns false when
    /// there was nothing to cancel, so the screen handles it.
    public func cancel() -> Bool {
        guard isScrubbing, let target else { return false }
        log?("input menu: cancel scrub, back to \(origin.clock)")
        head = nil
        scanning = nil
        if resumeOnCancel { target.play() }
        return true
    }

    // MARK: Internals

    private func beginScrubIfNeeded() {
        guard head == nil, let target else { return }
        origin = target.position
        resumeOnCancel = target.isPlaying
        if target.isPlaying { target.pause() }
        head = origin
    }

    private func move(to time: Duration) {
        guard let target else { return }
        let end = max(.zero, target.length - .seconds(1))
        head = min(max(.zero, time), end)
    }

    private func commit(_ time: Duration) {
        guard let target else { return }
        head = nil
        scanning = nil
        show(.play)
        Task {
            await target.seek(to: time)
            target.play()
        }
    }

    /// Touch travel → time. A full swipe covers about an eighth of the video
    /// (90 s – 15 min); slow, careful movement is finer, a quick flick coarser.
    func seconds(forPad travel: Double, speed: Double) -> Duration {
        guard let target else { return .zero }
        let perPad = min(max(target.length.secondsValue / 8, 90), 900)
        let gain = speed < 0.3 ? 0.5 : speed < 1 ? 1 : min(speed, 4)
        return .seconds(travel * perPad * gain)
    }

    private func show(_ kind: Feedback.Kind) {
        feedbackCount += 1
        feedback = Feedback(kind: kind, id: feedbackCount)
    }
}

extension Duration {
    var secondsValue: Double {
        let (s, atto) = components
        return Double(s) + Double(atto) / 1e18
    }

    /// "1:02:03" / "2:03" (diagnostics).
    var clock: String {
        let total = Int(max(0, secondsValue.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
