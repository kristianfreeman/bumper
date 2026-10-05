import os
import QuartzCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Measures render hitches with a CADisplayLink (the Mac's comes from its
/// screen, macOS 14+). A frame that arrives later
/// than its target timestamp contributes its lateness to "hitch time"; the
/// hitch ratio (ms of hitch per second) is Apple's own smoothness metric and is
/// what we budget against.
///
/// Running a display link costs a little power, so it's only active while the
/// HUD is visible or under UI tests.
@MainActor
public final class HitchMonitor {
    public static let shared = HitchMonitor()

    private var link: CADisplayLink?
    private var expectedTimestamp: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var windowHitch: CFTimeInterval = 0
    private var lastActivity: CFTimeInterval = 0
    private var totalActive: CFTimeInterval = 0
    private var totalHitch: CFTimeInterval = 0

    public private(set) var isRunning = false

    public func start() {
        guard link == nil else { return }
        #if canImport(UIKit)
        let link = CADisplayLink(target: Proxy(self), selector: #selector(Proxy.tick(_:)))
        #else
        guard let link = NSScreen.main?.displayLink(target: Proxy(self), selector: #selector(Proxy.tick(_:))) else { return }
        #endif
        link.add(to: .main, forMode: .common)
        self.link = link
        isRunning = true
        windowStart = 0
    }

    /// Call on user interaction (focus moves, scrolls). Like Apple's hitch
    /// ratio, we only score windows where the user is actually interacting:
    /// an idle screen can't hitch in a way anyone sees.
    public func noteActivity() {
        lastActivity = CACurrentMediaTime()
    }

    /// Start a fresh measurement (cumulative totals included). Call together
    /// with `Metrics.shared.reset()`, or totals from before would leak in.
    public func resetTotals() {
        totalActive = 0
        totalHitch = 0
        windowHitch = 0
        windowStart = 0
    }

    public func stop() {
        link?.invalidate()
        link = nil
        isRunning = false
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if windowStart == 0 {
            windowStart = now
            expectedTimestamp = link.targetTimestamp
            return
        }
        let frameBudget = link.targetTimestamp - link.timestamp
        let late = now - expectedTimestamp
        let active = now - lastActivity < 1.5
        // Only frames during interaction count — the same frames frameTime
        // scores. (Counting idle-time lateness, e.g. during launch, and then
        // reporting it in the first active window inflated the ratio.)
        if active {
            if late > frameBudget * 0.5 {
                windowHitch += late
                // Which moment hitched: line it up with signposts/logs.
                Perf.logger("hitch").info("hitch \(Int(late * 1_000), privacy: .public) ms late")
            }
            Metrics.shared.record(.frameTime, value: (now - (expectedTimestamp - frameBudget)) * 1_000)
        }
        expectedTimestamp = link.targetTimestamp

        let elapsed = now - windowStart
        if elapsed >= 1 {
            if active {
                // Apple's definition: total hitch time / total interaction time.
                totalActive += elapsed
                totalHitch += windowHitch
                Metrics.shared.record(.hitchRatio, value: (totalHitch * 1_000) / totalActive)
                Metrics.shared.record(.hitchWindow, value: (windowHitch * 1_000) / elapsed)
            }
            windowStart = now
            windowHitch = 0
        }
    }

    /// CADisplayLink retains its target; the proxy breaks the cycle.
    /// The link is scheduled on the main run loop, so the proxy is main-actor.
    @MainActor
    private final class Proxy: NSObject {
        weak var owner: HitchMonitor?
        init(_ owner: HitchMonitor) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) {
            owner?.tick(link)
        }
    }
}
