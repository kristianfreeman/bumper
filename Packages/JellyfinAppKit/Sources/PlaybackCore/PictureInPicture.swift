public import Observation

/// Picture in Picture for one backend (iPhone, iPad, Mac; the TV has none):
/// the picture floats in the system's window while you're elsewhere. The
/// backend drives the system's controller and reports back here; the player
/// reads `isPossible` and `isActive` and hears back through the handlers.
@MainActor
@Observable
public final class PictureInPicture {
    /// The system would float the picture now (an item showing, PiP allowed).
    public private(set) var isPossible = false
    public private(set) var isActive = false

    /// The player's: the picture is floating.
    @ObservationIgnored public var didStart: (() -> Void)?
    /// The player's: the window's restore button. Bring the player's screen
    /// back; the picture goes back into it once this returns.
    @ObservationIgnored public var restoreScreen: (() async -> Void)?
    /// The player's: it stopped floating (closed, or after a restore).
    @ObservationIgnored public var didStop: (() -> Void)?

    @ObservationIgnored private let starts: () -> Void
    @ObservationIgnored private let stops: () -> Void

    public init(start: @escaping () -> Void, stop: @escaping () -> Void) {
        starts = start
        stops = stop
    }

    public func start() { starts() }
    public func stop() { stops() }

    // MARK: From the backend

    public func setPossible(_ possible: Bool) {
        if possible != isPossible { isPossible = possible }
    }

    public func started() {
        isActive = true
        didStart?()
    }

    public func restore() async {
        await restoreScreen?()
    }

    /// Stopped, or failed to start.
    public func stopped() {
        isActive = false
        didStop?()
    }
}

/// What the player does as the picture floats and comes back. The PiP
/// button floats it and closes the player's screen, so you can browse;
/// leaving the app floats it on its own and the screen stays, ready for
/// your return. Restoring brings the screen back where it was; closing the
/// window with the screen gone ends playback (there's nothing left to watch).
public struct PictureInPictureFlow: Sendable, Equatable {
    public enum Action: Sendable, Equatable { case none, closeScreen, reopenScreen, endPlayback }

    /// The player's screen is closed while the picture floats.
    public private(set) var screenClosed = false
    private var asked = false
    private var restoring = false

    public init() {}

    /// The PiP button was pressed: once it floats, the screen closes.
    public mutating func ask() { asked = true }

    public mutating func started() -> Action {
        defer { asked = false }
        guard asked else { return .none }
        screenClosed = true
        return .closeScreen
    }

    public mutating func restore() -> Action {
        restoring = true
        guard screenClosed else { return .none }
        screenClosed = false
        return .reopenScreen
    }

    public mutating func stopped() -> Action {
        defer { asked = false; restoring = false; screenClosed = false }
        return screenClosed && !restoring ? .endPlayback : .none
    }
}
