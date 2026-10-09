import Foundation
import Synchronization

/// A thread off to the side that knocks on the main thread four times a
/// second and writes to the trace when it took longer than `threshold` to
/// answer — how long the app wasn't drawing or taking the remote. ("Froze"
/// on a TV, with the trace showing nothing else, is a line here or isn't.)
public enum MainThreadWatch {
    private static let started = Mutex(false)

    public static func start(threshold: Duration = .milliseconds(400)) {
        guard started.withLock({ let was = $0; $0 = true; return !was }) else { return }
        let wait = Int(threshold / .milliseconds(1))
        let thread = Thread {
            while true {
                let asked = ContinuousClock.now
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                if answered.wait(timeout: .now() + .milliseconds(wait)) == .timedOut {
                    answered.wait()
                    TraceFile.write("hang", "main thread blocked \(Int((ContinuousClock.now - asked) / .milliseconds(1))) ms")
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
        thread.name = "main-thread-watch"
        thread.qualityOfService = .utility
        thread.start()
    }
}
