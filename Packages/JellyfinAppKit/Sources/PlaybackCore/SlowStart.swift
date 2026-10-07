import AppCore
import Foundation

/// What the player says while a start is slow: where it's going, so a long
/// wait reads as work rather than a hang. Nothing for the first second —
/// a quick start shouldn't flash words up.
public enum SlowStart {
    public static var delay: Duration { Pace.of(.seconds(1)) }

    /// "Getting to 42:10…" for a resume, "Getting ready…" from the start;
    /// nil until it's been `delay`.
    public static func message(resumingAt start: Duration?, after waited: Duration) -> String? {
        guard waited >= delay else { return nil }
        if let start, start >= .seconds(1) { return "Getting to \(start.clockString)…" }
        return "Getting ready…"
    }
}
