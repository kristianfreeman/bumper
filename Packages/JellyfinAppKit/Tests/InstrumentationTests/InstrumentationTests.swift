@testable import Instrumentation
import Testing

@Suite("Metrics")
struct MetricsTests {
    @Test func percentilesOverSamples() throws {
        let m = Metrics()
        for v in 1...100 { m.record("t", value: Double(v)) }
        let s = try #require(m.summary("t"))
        #expect(s.count == 100)
        #expect(s.min == 1 && s.max == 100)
        #expect((50...51).contains(s.p50))
        #expect((94...96).contains(s.p95))
        #expect(s.last == 100)
    }

    @Test func ringBufferKeepsMostRecentWindow() throws {
        let m = Metrics()
        for v in 0..<(Metrics.capacity + 100) { m.record("r", value: Double(v)) }
        let s = try #require(m.summary("r"))
        #expect(s.count == Metrics.capacity + 100)
        #expect(s.min == 100)
        #expect(s.last == Double(Metrics.capacity + 99))
    }

    @Test func budgetsEvaluate() {
        let m = Metrics()
        m.record(.imageDecode, value: 3)
        m.record(.timeToFirstFrame, value: 5_000)
        let failing = m.violations().map(\.0.metric)
        #expect(failing == [.timeToFirstFrame])
    }

    @Test func snapshotJSONIsMachineReadable() throws {
        let m = Metrics()
        m.record(.homeLoad, .milliseconds(42))
        let json = m.snapshotJSON()
        #expect(json.contains("\"home.load\""))
        #expect(json.contains("\"p95\":42"))
    }

    @Test(.enabled(if: isOptimized, "timing budget: optimized builds only")) func recordingIsCheapEnoughForRenderLoops() {
        let m = Metrics()
        let t = ContinuousClock().measure { for i in 0..<100_000 { m.record("hot", value: Double(i)) } }
        #expect(t / 100_000 < .microseconds(2), "record() costs \(t / 100_000)")
    }
}

/// Timing budgets are only meaningful in optimized builds; debug runs skip
/// them (`scripts/test.sh perf` runs them with -c release).
let isOptimized: Bool = {
    #if DEBUG
    false
    #else
    true
    #endif
}()
