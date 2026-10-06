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
    /// Up/down (click or swipe): bring up the icon row.
    let onVertical: () -> Void

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
        var onVertical: (() -> Void)?
        var showsControls: (() -> Bool)?
        private var recognizers: [UIGestureRecognizer] = []
        private var playPause: PressRecognizer?
        private weak var host: UIView?
        private var lastTranslation: CGPoint = .zero
        private var verticalFired = false
        private var panStart: ContinuousClock.Instant?
        private var holdTask: Task<Void, Never>?
        private var holding = false

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
            TraceFile.write("input", "remote gestures installed on \(type(of: window))")
        }

        func uninstall() {
            if !recognizers.isEmpty { TraceFile.write("input", "remote gestures removed (\(recognizers.count))") }
            holdTask?.cancel()
            for r in recognizers { r.view?.removeGestureRecognizer(r) }
            recognizers = []
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
                // A mostly-vertical swipe (not while scrubbing) brings up the icons.
                if !transport.isScrubbing, !verticalFired, abs(t.y) > 280, abs(t.y) > abs(t.x) * 2 {
                    verticalFired = true
                    onVertical?()
                    return
                }
                guard !verticalFired else { return }
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
                onVertical?()
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
