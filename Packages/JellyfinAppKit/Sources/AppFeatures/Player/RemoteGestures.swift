#if os(tvOS)
import GameController
import Instrumentation
import PlaybackCore
import SwiftUI
import UIKit

/// The Siri Remote, read the way UIKit reports it: clicks on the clickpad
/// arrive as arrow presses and a finger on the touch surface as a pan — two
/// different things. (SwiftUI's move commands deliver both as "left/right",
/// so a swipe and a click were indistinguishable.)
///
/// Installs recognizers on the player's window while it's on screen; they
/// act only while the video itself has focus (`active`), except Play/Pause.
struct RemoteGestures: UIViewRepresentable {
    let transport: TransportModel
    /// The video has focus (no icon, no menu).
    let active: Bool
    /// Select: first, bring the controls up (true: done, nothing to toggle).
    var showsControls: () -> Bool = { false }
    /// Right while an intro (a recap, a preview) plays: skip it (true: done).
    var skipsSegment: () -> Bool = { false }
    /// Up or down (click or swipe; true: up): Audio & Subtitles, or More.
    let onVertical: (_ up: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.coordinator = context.coordinator
        update(context.coordinator)
        return view
    }

    func updateUIView(_ view: InstallerView, context: Context) {
        update(context.coordinator)
    }

    static func dismantleUIView(_ view: InstallerView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    private func update(_ c: Coordinator) {
        c.transport = transport
        c.active = active
        c.onVertical = onVertical
        c.showsControls = showsControls
        c.skipsSegment = skipsSegment
    }

    final class InstallerView: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { coordinator?.install(on: window) } else { coordinator?.uninstall() }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var transport: TransportModel?
        var active = false
        var onVertical: ((Bool) -> Void)?
        var showsControls: (() -> Bool)?
        var skipsSegment: (() -> Bool)?
        private var recognizers: [UIGestureRecognizer] = []
        private var playPause: PressRecognizer?
        private weak var host: UIView?
        private var lastTranslation: CGPoint = .zero
        private var verticalFired = false
        private var panStart: ContinuousClock.Instant?
        private var holdTask: Task<Void, Never>?
        private var holding = false
        /// The ring: where the finger was on it, how far it's gone round,
        /// and whether that's a jog (then the pan doesn't scrub as well).
        private var ringAngle: Double?
        private var ringTravel: Double = 0
        private var jogging = false
        private var pads: [GCMicroGamepad] = []
        private var padObserver: NSObjectProtocol?

        /// The touch surface, in the units UIKit reports for indirect touches
        /// (a full swipe across the pad ≈ a screen width).
        private static let padWidth: CGFloat = 1920

        func install(on window: UIView) {
            guard recognizers.isEmpty else { return }
            host = window
            TraceFile.write("input", "remote: " + (GCController.controllers().map(\.productCategory).joined(separator: ", ").nilIfEmpty ?? "none seen"))
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]

            let arrows = PressRecognizer(types: [.leftArrow, .rightArrow, .upArrow, .downArrow])
            arrows.onBegan = { [weak self] in self?.arrowBegan($0) }
            arrows.onEnded = { [weak self] in self?.arrowEnded($0) }

            let select = PressRecognizer(types: [.select])
            select.onEnded = { [weak self] _ in
                guard let self else { return }
                // Not mid-scrub (Select there plays from the head).
                if self.transport?.isScrubbing != true, self.showsControls?() == true { TraceFile.write("input", "select: controls up"); return }
                self.transport?.togglePlayPause(source: "select")
            }

            let playPause = PressRecognizer(types: [.playPause])
            playPause.onEnded = { [weak self] _ in self?.transport?.togglePlayPause(source: "Play/Pause") }
            self.playPause = playPause

            for r in [pan, arrows, select, playPause] as [UIGestureRecognizer] {
                r.delegate = self
                r.cancelsTouchesInView = false
                r.delaysTouchesBegan = false
                window.addGestureRecognizer(r)
            }
            recognizers = [pan, arrows, select, playPause]
            watchRing()
            TraceFile.write("input", "remote gestures installed on \(type(of: window))")
        }

        // MARK: The ring

        /// The touch surface's absolute position (GameController): a finger
        /// going round near the edge is the ring's jog, not a swipe.
        private func watchRing() {
            for controller in GCController.controllers() { watch(controller) }
            // A remote that connects later (woken, paired): watch it too.
            padObserver = NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for controller in GCController.controllers() { self.watch(controller) }
                }
            }
        }

        private func watch(_ controller: GCController) {
            guard let pad = controller.microGamepad, !pads.contains(where: { $0 === pad }) else { return }
            pad.reportsAbsoluteDpadValues = true
            pad.dpad.valueChangedHandler = { [weak self] _, x, y in
                MainActor.assumeIsolated { self?.ringMoved(x: Double(x), y: Double(y)) }
            }
            pads.append(pad)
        }

        private func ringMoved(x: Double, y: Double) {
            guard active, let transport else { return }
            let r = (x * x + y * y).squareRoot()
            // Off the edge (lifted, or moving in to the middle): the turn ends.
            guard r > 0.7 else {
                if jogging { TraceFile.write("input", "ring: jog ended at head \(transport.head.map { "\(Int($0.components.seconds)) s" } ?? "-")") }
                ringAngle = nil
                ringTravel = 0
                jogging = false
                return
            }
            let angle = atan2(y, x)
            defer { ringAngle = angle }
            guard let last = ringAngle else { return }
            var d = angle - last
            if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
            ringTravel += d
            // A sixth of a turn one way: it's going round, not a swipe across.
            if !jogging, abs(ringTravel) > .pi / 3 {
                jogging = true
                TraceFile.write("input", "ring: jog")
            }
            if jogging { transport.jog(radians: -d) }               // clockwise (angle falling) is forward
        }

        func uninstall() {
            if !recognizers.isEmpty { TraceFile.write("input", "remote gestures removed (\(recognizers.count))") }
            holdTask?.cancel()
            for r in recognizers { r.view?.removeGestureRecognizer(r) }
            recognizers = []
            for pad in pads {
                pad.dpad.valueChangedHandler = nil
                pad.reportsAbsoluteDpadValues = false
            }
            pads = []
            if let padObserver { NotificationCenter.default.removeObserver(padObserver) }
            padObserver = nil
        }

        // MARK: Delegate

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
            g === playPause || active
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { active }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        // MARK: Touch surface

        @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
            guard let transport, let view = pan.view else { return }
            let t = pan.translation(in: view)
            switch pan.state {
            case .began:
                lastTranslation = .zero
                verticalFired = false
                panStart = .now
                transport.panBegan()
            case .changed:
                let dx = (t.x - lastTranslation.x) / Self.padWidth
                lastTranslation = t
                // A mostly-vertical swipe (not while scrubbing): up or down, as a click would.
                if !transport.isScrubbing, !verticalFired, abs(t.y) > 280, abs(t.y) > abs(t.x) * 2 {
                    verticalFired = true
                    onVertical?(t.y < 0)
                    return
                }
                guard !verticalFired, !jogging else { return }
                let speed = abs(pan.velocity(in: view).x) / Self.padWidth
                transport.panChanged(dx: Double(dx), speed: Double(speed))
            case .ended, .cancelled, .failed:
                let ms = panStart.map { Int($0.duration(to: .now).milliseconds) } ?? 0
                TraceFile.write("input", "pan \(Int(t.x)),\(Int(t.y)) pt in \(ms) ms")
                transport.panEnded()
            default:
                break
            }
        }

        // MARK: Clicks and holds

        private func arrowBegan(_ type: UIPress.PressType) {
            switch type {
            case .upArrow, .downArrow:
                onVertical?(type == .upArrow)
            case .leftArrow, .rightArrow:
                let direction: TransportModel.Direction = type == .leftArrow ? .backward : .forward
                holdTask?.cancel()
                holding = false
                // Held past 0.4 s: a scan, not a click.
                holdTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(400))
                    guard let self, !Task.isCancelled else { return }
                    self.holding = true
                    self.transport?.holdBegan(direction)
                }
            default:
                break
            }
        }

        private func arrowEnded(_ type: UIPress.PressType) {
            guard type == .leftArrow || type == .rightArrow else { return }
            holdTask?.cancel()
            if holding {
                holding = false
                transport?.holdEnded()
            } else if type == .rightArrow, transport?.isScrubbing != true, skipsSegment?() == true {
                TraceFile.write("input", "right: skipped a segment")
            } else {
                transport?.click(type == .leftArrow ? .backward : .forward)
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Reports presses of the given types without claiming them (the focused
/// SwiftUI view still sees them).
final class PressRecognizer: UIGestureRecognizer {
    var onBegan: ((UIPress.PressType) -> Void)?
    var onEnded: ((UIPress.PressType) -> Void)?

    init(types: [UIPress.PressType]) {
        super.init(target: nil, action: nil)
        allowedPressTypes = types.map { NSNumber(value: $0.rawValue) }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        for press in presses { onBegan?(press.type) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        for press in presses { onEnded?(press.type) }
        state = .failed                                  // reset for the next press
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        state = .failed
    }
}
#endif
