import Foundation

/// Performance budgets are product requirements, not suggestions. They're
/// evaluated by unit tests, by UI tests (which read the HUD's accessibility
/// value), and live in the debug HUD (red when blown).
///
/// Tighten these over time; never loosen one without a written reason.
public struct PerformanceBudget: Sendable, Codable, Equatable {
    public enum Statistic: String, Sendable, Codable { case p50, p95, max, last }

    public let metric: MetricKey
    public let statistic: Statistic
    public let limit: Double

    public init(_ metric: MetricKey, _ statistic: Statistic, under limit: Double) {
        self.metric = metric
        self.statistic = statistic
        self.limit = limit
    }

    public static let defaults: [PerformanceBudget] = [
        // Cold launch to first shelf painted from cache (ms).
        .init(.launchToFirstContent, .max, under: 1_200),
        .init(.homeLoad, .p95, under: 800),
        .init(.detailLoad, .p95, under: 400),
        .init(.apiDecode, .p95, under: 15),
        // Image decode happens off-main, but must keep up with fast scrolling.
        .init(.imageDecode, .p95, under: 12),
        .init(.blurHashDecode, .p95, under: 2),
        // Apple's guidance: < 5 ms/s is "good", > 10 ms/s is "critical".
        // Cumulative ratio, so `.last` is the session-wide figure.
        .init(.hitchRatio, .last, under: 5),
        // Press Play → first frame on screen.
        .init(.timeToFirstFrame, .p95, under: 1_500),
        .init(.seekLatency, .p95, under: 600),
    ]

    public enum Verdict: Sendable, Equatable {
        case pass(Double)
        case fail(Double)
        case noData
    }

    public func evaluate(_ summary: MetricSummary?) -> Verdict {
        guard let summary else { return .noData }
        let value: Double = switch statistic {
        case .p50: summary.p50
        case .p95: summary.p95
        case .max: summary.max
        case .last: summary.last
        }
        return value < limit ? .pass(value) : .fail(value)
    }
}

extension Metrics {
    /// Returns the budgets that currently fail.
    public func violations(of budgets: [PerformanceBudget] = PerformanceBudget.defaults) -> [(PerformanceBudget, Double)] {
        let snap = snapshot()
        return budgets.compactMap { budget in
            if case .fail(let v) = budget.evaluate(snap[budget.metric]) { return (budget, v) }
            return nil
        }
    }
}
