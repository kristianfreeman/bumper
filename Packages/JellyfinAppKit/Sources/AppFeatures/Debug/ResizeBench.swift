#if os(macOS)
import AppKit
import Instrumentation
import QuartzCore

/// `-resizeBench`: drives the main window through a live-drag-like sweep
/// (960×600 → 1600×1000 and back, one step per display frame, ~3 s) and
/// traces how long each step keeps the main thread (layout + display of the
/// new size) and the display link's frame times. A step over 8.3 ms is a
/// dropped frame at 120 Hz. Wrapped in the live-resize notifications a drag
/// sends, so code that waits for the drag to end is exercised as a real one.
@MainActor
enum ResizeBench {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-resizeBench") }

    static func run(after delay: Duration = .seconds(4)) async {
        guard enabled else { return }
        try? await Task.sleep(for: delay)
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
            TraceFile.write("benchmark", "resize: no window"); return
        }
        let origin = NSPoint(x: 0, y: 0)
        let steps = 180                                   // 1.5 s each way at 120 Hz
        var sizes: [NSSize] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let e = 0.5 - 0.5 * cos(t * .pi)
            sizes.append(NSSize(width: 960 + 640 * e, height: 600 + 400 * e))
        }
        sizes += sizes.reversed()
        window.setFrame(NSRect(origin: origin, size: sizes[0]), display: true)
        try? await Task.sleep(for: .milliseconds(500))

        Metrics.shared.reset()
        HitchMonitor.shared.start()
        HitchMonitor.shared.resetTotals()
        NotificationCenter.default.post(name: NSWindow.willStartLiveResizeNotification, object: window)
        var costs: [Double] = []
        let start = CACurrentMediaTime()
        for size in sizes {
            HitchMonitor.shared.noteActivity()
            let t0 = CACurrentMediaTime()
            window.setFrame(NSRect(origin: origin, size: size), display: true)
            window.displayIfNeeded()
            CATransaction.flush()
            costs.append((CACurrentMediaTime() - t0) * 1_000)
            // The next frame: yield to the run loop so the display link and
            // any work the resize queued (tasks, image loads) run as in a drag.
            try? await Task.sleep(for: .milliseconds(8))
        }
        NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: window)
        let total = CACurrentMediaTime() - start
        try? await Task.sleep(for: .milliseconds(300))

        let sorted = costs.sorted()
        func pct(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        func ms(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1))) }
        let over = costs.filter { $0 > 8.3 }.count
        let spikes = costs.enumerated().filter { $0.element > 20 }.map { "#\($0.offset) \(Int(sizes[$0.offset].width))w \(ms($0.element))" }
        if !spikes.isEmpty { TraceFile.write("benchmark", "resize spikes: \(spikes.joined(separator: ", "))") }
        let label = ProcessInfo.processInfo.arguments.contains("-autoplay") ? "player" : (UserDefaults.standard.string(forKey: "route") ?? "home")
        TraceFile.write("benchmark", "resize [\(label)]: \(costs.count) steps in \(ms(total)) s, step p50 \(ms(pct(0.5))) ms, p95 \(ms(pct(0.95))) ms, max \(ms(sorted.last ?? 0)) ms, \(over) over 8.3 ms")
        Benchmark.traceFrames("resize [\(label)] display")
        TraceFile.write("benchmark", "RESIZE DONE")
    }
}
#endif
