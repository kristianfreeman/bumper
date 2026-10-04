public import Foundation
import Synchronization

/// Key playback events are appended to Library/Caches/perf/trace.log (fresh
/// each launch, a few KB), so what happened on a real Apple TV can be read
/// back with `devicectl device copy from` — the device's system log needs root.
/// Always on; `-noTraceFile` turns it off.
public enum TraceFile {
    public static let enabled = !ProcessInfo.processInfo.arguments.contains("-noTraceFile")

    public static let directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "perf", directoryHint: .isDirectory)

    private static let handle = Mutex<FileHandle?>(nil)
    private static let start = ContinuousClock.now

    public static func write(_ category: String, _ message: String) {
        guard enabled else { return }
        let t = start.duration(to: .now).components
        let line = String(format: "%8.3f [%@] %@\n", Double(t.seconds) + Double(t.attoseconds) / 1e18, category, message)
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
