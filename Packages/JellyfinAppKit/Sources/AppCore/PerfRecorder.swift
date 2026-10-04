public import Foundation
public import Instrumentation
import Synchronization

/// Persists performance snapshots inside the app's own container, so they can
/// be pulled off ANY device (`scripts/pull-device-metrics.sh`, which uses
/// `devicectl device copy from --domain-type appDataContainer`) — no root, no
/// Instruments, no log archive. This is how "it feels janky on the 2017 Apple
/// TV" becomes numbers.
///
/// Files (Library/Caches/perf/):
/// - `latest.json`   — rolling snapshot, rewritten every 10 s while metrics change
/// - `session-<timestamp>.json` — final snapshot of each session (on background)
public final class PerfRecorder: Sendable {
    public static let shared = PerfRecorder()

    public struct Snapshot: Codable, Sendable {
        public var device: String
        public var os: String
        public var app: String
        public var startedAt: Date
        public var writtenAt: Date
        public var metrics: [String: MetricSummary]
        public var budgetFailures: [String]
    }

    private let directory: URL
    private let metrics: Metrics
    private let startedAt = Date()
    private let state = Mutex<(task: Task<Void, Never>?, lastCount: Int)>((nil, -1))

    public init(directory: URL? = nil, metrics: Metrics = .shared) {
        self.metrics = metrics
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "perf", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public var latestURL: URL { directory.appending(path: "latest.json") }

    /// Starts the periodic writer (idempotent).
    public func start(interval: Duration = .seconds(10)) {
        state.withLock { s in
            guard s.task == nil else { return }
            s.task = Task.detached(priority: .utility) { [self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    writeIfChanged()
                }
            }
        }
    }

    /// Writes `latest.json` now if anything was recorded since the last write.
    public func writeIfChanged() {
        let snap = metrics.snapshot()
        let count = snap.values.reduce(0) { $0 + $1.count }
        let changed = state.withLock { s -> Bool in
            guard count != s.lastCount else { return false }
            s.lastCount = count
            return true
        }
        if changed { write(to: latestURL, metrics: snap) }
    }

    /// Final snapshot for this session (call on background / exit).
    public func writeSession() {
        let stamp = ISO8601DateFormatter().string(from: startedAt).replacingOccurrences(of: ":", with: "-")
        write(to: directory.appending(path: "session-\(stamp).json"), metrics: metrics.snapshot())
        writeIfChanged()
    }

    func write(to url: URL, metrics summaries: [MetricKey: MetricSummary]) {
        let failures = metrics.violations().map { "\($0.0.metric.rawValue) \($0.0.statistic.rawValue)=\(Int($0.1)) ≥ \(Int($0.0.limit))" }
        let snapshot = Snapshot(
            device: Self.deviceModel,
            os: ProcessInfo.processInfo.operatingSystemVersionString,
            app: "\(Brand.version) (\(Brand.build))",
            startedAt: startedAt,
            writtenAt: Date(),
            metrics: Dictionary(uniqueKeysWithValues: summaries.map { ($0.key.rawValue, $0.value) }),
            budgetFailures: failures
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Model identifier without the simulator suffix (for capability tables).
    public static var hardwareModel: String {
        deviceModel.replacingOccurrences(of: " (simulator)", with: "")
    }

    /// e.g. "AppleTV6,2" (Apple TV 4K, 2017). Simulators report their host model.
    public static let deviceModel: String = {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim + " (simulator)" }
        var info = utsname()
        unsafe uname(&info)
        return unsafe withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }()
}
