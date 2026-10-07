#if os(tvOS) || os(iOS) || os(macOS)
import PlaybackCore

#if os(iOS)
import UIKit
import AVKit
import Foundation
import Instrumentation
import Synchronization
@preconcurrency import VLCKit

// VLCKit 4's Picture in Picture (VLCDrawable.h): its video output on Apple
// platforms draws into an AVSampleBufferDisplayLayer ("samplebufferdisplay",
// the default), and when the drawable conforms to
// `VLCPictureInPictureDrawable` it opens its "pictureinpicture" module: an
// AVPictureInPictureController on that layer. The drawable hands it the
// media controls PiP's window uses (`VLCPictureInPictureMediaControlling`)
// and gets the controller back once it's ready
// (`VLCPictureInPictureWindowControlling`: start, stop, started/stopped).
// The iOS and tvOS builds have that module; the Mac build doesn't (no
// VLCPictureInPictureController in it), so VLCKit items don't float there.

/// VLCKit's drawable on iPhone and iPad, offering Picture in Picture.
final class VLCSurface: UIView, VLCPictureInPictureDrawable {
    nonisolated let floating: VLCFloating

    init(floating: VLCFloating) {
        self.floating = floating
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // Called by VLCKit's video output, on its own thread.
    nonisolated func mediaController() -> any VLCPictureInPictureMediaControlling { floating.media }
    nonisolated func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)? { floating.readyHandler() }
}

/// VLCKit's Picture in Picture, for the player. VLCKit only reports started
/// and stopped; the window's restore button is heard from the system's
/// controller itself (`RestoreRelay`).
@MainActor
final class VLCFloating {
    nonisolated let media = FloatingMedia()
    private(set) lazy var pip = PictureInPicture(start: { [weak self] in self?.window?.startPictureInPicture() },
                                                 stop: { [weak self] in self?.window?.stopPictureInPicture() })
    private var window: (any VLCPictureInPictureWindowControlling)?
    private var relay: RestoreRelay?
    private var possible: NSKeyValueObservation?
    /// The engine is opening the item again (a new audio route, software
    /// decode): its video output closes, and the floating picture with it.
    var reopening = false

    nonisolated func readyHandler() -> ((any VLCPictureInPictureWindowControlling)?) -> Void {
        { [weak self] given in
            guard let given else { return }
            nonisolated(unsafe) let controller = given
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.ready(controller) } }
        }
    }

    /// A new video output (an item opened) brings a new controller.
    private func ready(_ controller: any VLCPictureInPictureWindowControlling) {
        window = controller
        controller.stateChangeEventHandler = { [weak self] started in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.stateChanged(started) } }
        }
        relay = nil
        possible = nil
        // The system's controller behind VLCKit's (its `avPipController`,
        // not in VLCKit's headers): for "possible", starting on its own as
        // you leave the app, and the restore button.
        let object = controller as AnyObject
        if object.responds(to: NSSelectorFromString("avPipController")),
           let system = (controller as? NSObject)?.value(forKey: "avPipController") as? AVPictureInPictureController {
            system.canStartPictureInPictureAutomaticallyFromInline = true
            let relay = RestoreRelay(original: system.delegate) { [weak self] done in
                nonisolated(unsafe) let done = done
                Task { @MainActor in
                    await self?.pip.restore()
                    done(true)
                }
            }
            system.delegate = relay
            self.relay = relay
            possible = system.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] system, _ in
                let now = system.isPictureInPicturePossible
                Task { @MainActor in self?.pip.setPossible(now) }
            }
            TraceFile.write("vlc", "picture in picture ready")
        } else {
            pip.setPossible(true)
            TraceFile.write("vlc", "picture in picture ready (no system controller: restore guessed)")
        }
    }

    private func stateChanged(_ started: Bool) {
        TraceFile.write("vlc", "picture in picture \(started ? "on" : "off")\(reopening ? " (reopening the item)" : "")")
        if started { pip.started(); return }
        // Not the window's buttons: the item opening again closed it. Or
        // no restore button to hear: still playing, it was a restore (the
        // window's close pauses first).
        if reopening || (relay == nil && media.isMediaPlaying()) {
            reopening = false
            Task {
                await pip.restore()
                pip.stopped()
            }
        } else {
            pip.stopped()
        }
    }

    /// Playback stopped: nothing to float.
    func closed() {
        window = nil
        possible = nil
        relay = nil
        pip.setPossible(false)
    }

    /// Whenever the time, length or playing state changes (VLCKit asks).
    func update(time: Duration, length: Duration?, playing: Bool) {
        let changed = media.update(time: time, length: length ?? .zero, playing: playing)
        if changed { window?.invalidatePlaybackState() }
    }
}

/// What PiP's window reads and presses. Asked from any thread: answers from
/// the last state the engine gave it, and presses go to the engine on main.
final class FloatingMedia: NSObject, VLCPictureInPictureMediaControlling, Sendable {
    private struct State { var time: Int64 = 0; var length: Int64 = 0; var playing = false }
    private let state = Mutex(State())
    nonisolated(unsafe) weak var engine: VLCEngine?

    /// True when the length or playing state changed (the time alone moves on its own).
    func update(time: Duration, length: Duration, playing: Bool) -> Bool {
        state.withLock { s in
            let changed = s.length != Int64(length.milliseconds) || s.playing != playing
            s = State(time: Int64(time.milliseconds), length: Int64(length.milliseconds), playing: playing)
            return changed
        }
    }

    func play() { onMain { $0.play() } }
    func pause() { onMain { $0.pause() } }

    func seek(by offset: Int64, completion: (() -> Void)!) {
        nonisolated(unsafe) let completion = completion
        onMain { engine in
            Task {
                await engine.seek(to: max(.zero, engine.currentTime + .milliseconds(offset)))
                completion?()
            }
        }
    }

    func mediaLength() -> Int64 { state.withLock { $0.length } }
    func mediaTime() -> Int64 { state.withLock { $0.time } }
    func isMediaSeekable() -> Bool { true }
    func isMediaPlaying() -> Bool { state.withLock { $0.playing } }

    private func onMain(_ action: @escaping @MainActor (VLCEngine) -> Void) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let engine = self?.engine else { return }
                action(engine)
            }
        }
    }
}

/// Stands in front of VLCKit's controller as the system controller's
/// delegate, to hear the restore button (VLCKit doesn't ask), and hands it
/// everything else.
private final class RestoreRelay: NSObject, AVPictureInPictureControllerDelegate {
    private weak var original: (any AVPictureInPictureControllerDelegate)?
    private let restore: (@escaping (Bool) -> Void) -> Void

    init(original: (any AVPictureInPictureControllerDelegate)?, restore: @escaping (@escaping (Bool) -> Void) -> Void) {
        self.original = original
        self.restore = restore
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        restore(completionHandler)
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }
}
#else
/// VLCKit's drawable: a plain view (no Picture in Picture for VLCKit here).
typealias VLCSurface = PlatformView
#endif
#endif
