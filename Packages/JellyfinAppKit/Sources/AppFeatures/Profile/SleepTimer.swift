import Foundation
import JellyfinAPI
import Observation

/// "Stop playing in 30 minutes" / "at the end of this episode". When it
/// expires the player fades audio out over `fadeLength` and stops; tvOS's
/// own sleep setting takes it from there (apps can't sleep the box).
@MainActor
@Observable
final class SleepTimer {
    enum Mode: Hashable {
        case off
        case minutes(Int)
        case endOfItem
    }

    static let presets = [15, 30, 60]

    /// "15 Minutes", "1 Hour", "1 Hour 30 Minutes".
    static func title(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) Minutes" : minutes == 60 ? "1 Hour" : "\(minutes / 60) Hour\(minutes >= 120 ? "s" : "") \(minutes % 60) Minutes"
    }
    /// The player's Stop Playing choices: "In 15 Minutes", "After This Episode".
    static func stopTitle(_ minutes: Int) -> String { "In " + title(minutes) }
    static func afterTitle(_ kind: ItemKind?) -> String {
        kind == .episode ? "After This Episode" : kind == .movie ? "After This Film" : "After This One"
    }
    static let fadeLength: Duration = .seconds(8)

    private(set) var mode: Mode = .off
    /// Time left for `.minutes`, refreshed every second (drives the label).
    private(set) var remaining: Duration?
    @ObservationIgnored private var deadline: ContinuousClock.Instant?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    var isActive: Bool { mode != .off }

    func set(_ new: Mode) {
        if case .minutes(let m) = new { start(new, length: .seconds(m * 60)) } else { start(new, length: nil) }
    }

    /// Test hook (`-sleepAfter <seconds>`): a timed mode with a short length.
    func set(seconds: Int) { start(.minutes(max(1, seconds / 60)), length: .seconds(seconds)) }

    private func start(_ new: Mode, length: Duration?) {
        mode = new
        ticker?.cancel()
        if let length {
            let end = ContinuousClock.now + length
            deadline = end
            remaining = length
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self else { return }
                    self.remaining = max(.zero, ContinuousClock.now.duration(to: end))
                }
            }
        } else {
            deadline = nil
            remaining = nil
        }
    }

    /// Finished (by time) — the player stops and calls `reset()`.
    var hasExpired: Bool { remaining == .zero }

    /// 1 → 0 across the last `fadeLength`; nil when not fading.
    var fadeVolume: Float? {
        guard case .minutes = mode, let deadline else { return nil }
        let left = ContinuousClock.now.duration(to: deadline)
        guard left < Self.fadeLength else { return nil }
        return Float(max(0, left / Self.fadeLength))
    }

    func reset() { set(.off) }

    /// "Sleep · 24m", "Sleep · End of episode", or nil when off.
    var shortLabel: String? {
        switch mode {
        case .off: nil
        case .endOfItem: "End of episode"
        case .minutes: remaining.map { r in
            let s = Int(r.components.seconds)
            return s >= 60 ? "\((s + 59) / 60)m" : "\(s)s"
        }
        }
    }
}
