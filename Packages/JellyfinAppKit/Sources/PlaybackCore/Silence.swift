/// Test runs and `-mock` launches play without sound: the test clips' tones
/// came out of the Mac's speakers through every simulator. `-sound` brings
/// it back. Set once at launch, before anything plays.
public enum Silence {
    nonisolated(unsafe) public static var on = false
}
