public import Foundation
import Synchronization

/// Key playback events are appended to Library/Caches/perf/trace.log (fresh
/// each launch, a few KB), so what happened on a real Apple TV can be read
/// back with `devicectl device copy from` — the device's system log needs root.
/// Always on; `-noTraceFile` turns it off.
public enum TraceFile {
    public static let enabled = !ProcessInfo.processInfo.arguments.contains("-noTraceFile")
    /// `-traceStderr`: also to standard error (a Mac app's sandboxed caches can't be read from a shell).
    static let toStderr = ProcessInfo.processInfo.arguments.contains("-traceStderr")

    public static let directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "perf", directoryHint: .isDirectory)

    /// Seconds per playback-stats line (`-statsWindow <s>`; the matrix uses
    /// short ones to measure a file in seconds, not half a minute).
    public static let statsWindow: Int = max(1, UserDefaults.standard.integer(forKey: "statsWindow").nonZero ?? 10)

    private static let handle = Mutex<FileHandle?>(nil)
    private static let start = ContinuousClock.now

    public static func write(_ category: String, _ message: String) {
        guard enabled else { return }
        let t = start.duration(to: .now).components
        let line = String(format: "%8.3f [%@] %@\n", Double(t.seconds) + Double(t.attoseconds) / 1e18, category, message)
        if toStderr { FileHandle.standardError.write(Data(line.utf8)) }
        handle.withLock { h in
            if h == nil {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appending(path: "trace.log")
                FileManager.default.createFile(atPath: url.path, contents: nil)
                h = try? FileHandle(forWritingTo: url)
            }
            try? h?.write(contentsOf: Data(line.utf8))
        }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
