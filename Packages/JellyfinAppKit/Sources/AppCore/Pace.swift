/// The app's deliberate waits (the player's controls hiding, a slow start's
/// words, a flash, focus settling before a page changes its backdrop or
/// prefetches) at a fifth under UI tests (`-quickTimers`): a test of one
/// takes moments, not its real seconds. Set once at launch; 1 for everyone
/// else.
public enum Pace {
    nonisolated(unsafe) public static var scale = 1.0

    /// `wait`, at this launch's pace.
    public static func of(_ wait: Duration) -> Duration { unsafe wait * scale }      // set before anything waits
}
