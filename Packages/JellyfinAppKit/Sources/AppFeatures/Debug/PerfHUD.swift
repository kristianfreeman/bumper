import Darwin
import DesignSystem
import Instrumentation
import SwiftUI

/// Always-on-top developer overlay: live p50/p95 for the hot paths, coloured
/// against `PerformanceBudget.defaults`, plus memory footprint and hitch rate.
///
/// Its accessibility value is the full metrics JSON, which is how XCUITests
/// read in-process measurements without any special test hooks.
struct PerfHUD: View {
    private let rows: [(String, MetricKey)] = [
        ("Launch → content", .launchToFirstContent),
        ("Home load", .homeLoad),
        ("Detail load", .detailLoad),
        ("API request", .apiRequest),
        ("JSON decode", .apiDecode),
        ("Image fetch", .imageFetch),
        ("Image decode", .imageDecode),
        ("Hitch ms/s", .hitchRatio),
        ("Playback info", .playbackInfo),
        ("TTFF", .timeToFirstFrame),
        ("Seek", .seekLatency),
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let snapshot = Metrics.shared.snapshot()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("PERF").font(.caption2.bold())
                    Spacer()
                    Text(memoryString).font(.caption2.monospacedDigit())
                }
                ForEach(rows, id: \.1) { label, key in
                    if let s = snapshot[key] {
                        HStack(spacing: 12) {
                            Circle().fill(color(for: key, summary: s)).frame(width: 10, height: 10)
                            Text(label).font(.caption2)
                            Spacer(minLength: 16)
                            Text("\(fmt(s.p50)) / \(fmt(s.p95))").font(.caption2.monospacedDigit())
                            Text("n=\(s.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: 520)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("perf.hud")
            .accessibilityValue(Metrics.shared.snapshotJSON())
        }
        .onAppear { HitchMonitor.shared.start() }
        .onDisappear { HitchMonitor.shared.stop() }
    }

    private func fmt(_ v: Double) -> String {
        v >= 100 ? String(Int(v.rounded())) : v.formatted(.number.precision(.fractionLength(1)))
    }

    private func color(for key: MetricKey, summary: MetricSummary) -> Color {
        guard let budget = PerformanceBudget.defaults.first(where: { $0.metric == key }) else { return .gray }
        switch budget.evaluate(summary) {
        case .pass: return .green
        case .fail: return .red
        case .noData: return .gray
        }
    }

    private var memoryString: String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "" }
        return "\(info.phys_footprint / 1_048_576) MB"
    }
}
