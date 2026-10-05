public import Foundation
import Instrumentation
import Synchronization

/// Fetches files as byte-range pieces over several connections at once (a
/// single connection rarely fills a home network's bandwidth), each piece a
/// download task of its own: resumable, and carried on by the system in a
/// background session while the app is suspended (iPhone, iPad).
///
/// It only moves bytes. The `DownloadStore` decides what to fetch and keeps
/// the bookkeeping; events reach it through `onEvent`.
public final class SegmentedDownloader: NSObject, URLSessionDownloadDelegate, Sendable {
    public enum Event: Sendable {
        /// More bytes arrived for a piece (`total` so far for that piece).
        case progress(download: String, piece: Int, received: Int64)
        /// A piece is complete, at `file` (moved out of the system's temporary location).
        case finished(download: String, piece: Int, file: URL)
        /// A piece failed; `resumeData` picks it up where it stopped, when there is some.
        case failed(download: String, piece: Int, resumeData: Data?, message: String)
    }

    /// What a task is for, in its `taskDescription` (survives an app relaunch
    /// in a background session): "<download>|<piece>".
    private static func tag(_ download: String, _ piece: Int) -> String { "\(download)|\(piece)" }
    private static func parse(_ tag: String?) -> (String, Int)? {
        guard let tag, let bar = tag.lastIndex(of: "|"), let piece = Int(tag[tag.index(after: bar)...]) else { return nil }
        return (String(tag[..<bar]), piece)
    }

    private let handler = Mutex<(@Sendable (Event) -> Void)?>(nil)
    private let piecesDirectory: URL
    private let sessionBox = Mutex<URLSession?>(nil)
    /// The system's completion handler for background events (iOS), called
    /// once the session has delivered them.
    let backgroundCompletion = Mutex<(@Sendable () -> Void)?>(nil)

    /// - Parameters:
    ///   - configuration: a background configuration in the app (iOS); a
    ///     default one on the Mac and in tests (which can inject a mock server).
    ///   - piecesDirectory: where finished pieces are moved to.
    public init(configuration: URLSessionConfiguration, piecesDirectory: URL) {
        self.piecesDirectory = piecesDirectory
        super.init()
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 7 * 24 * 3600
        sessionBox.withLock { $0 = URLSession(configuration: configuration, delegate: self, delegateQueue: nil) }
        try? FileManager.default.createDirectory(at: piecesDirectory, withIntermediateDirectories: true)
    }

    public func setBackgroundCompletion(_ completion: @escaping @Sendable () -> Void) {
        backgroundCompletion.withLock { $0 = completion }
    }

    public func setHandler(_ handler: @escaping @Sendable (Event) -> Void) {
        self.handler.withLock { $0 = handler }
    }

    private var session: URLSession { sessionBox.withLock { $0! } }

    /// Starts (or, with `resumeData`, resumes) one piece: `range` nil for the whole file.
    public func fetch(_ url: URL, range: ClosedRange<Int64>?, download: String, piece: Int, headers: [String: String] = [:], resumeData: Data? = nil) {
        let task: URLSessionDownloadTask
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            var request = URLRequest(url: url)
            for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
            if let range { request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range") }
            task = session.downloadTask(with: request)
        }
        task.taskDescription = Self.tag(download, piece)
        task.resume()
    }

    /// Stops every piece of a download; `keepResumeData` delivers each one's
    /// resume data as a `.failed` event (a pause), otherwise they're just gone.
    public func cancel(download: String, keepResumeData: Bool) async {
        let tasks = await session.allTasks
        for task in tasks {
            guard let (d, _) = Self.parse(task.taskDescription), d == download else { continue }
            if keepResumeData, let task = task as? URLSessionDownloadTask {
                task.cancel(byProducingResumeData: { _ in })          // delivered through didCompleteWithError
            } else {
                task.taskDescription = nil                            // no event for it
                task.cancel()
            }
        }
    }

    /// Pieces still in flight (after a relaunch: what the system carried on with).
    public func running() async -> [(download: String, piece: Int)] {
        await session.allTasks.compactMap { Self.parse($0.taskDescription) }.map { (download: $0.0, piece: $0.1) }
    }

    private func send(_ event: Event) { handler.withLock { $0 }?(event) }

    // MARK: URLSessionDownloadDelegate

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let (download, piece) = Self.parse(downloadTask.taskDescription) else { return }
        send(.progress(download: download, piece: piece, received: totalBytesWritten))
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (download, piece) = Self.parse(downloadTask.taskDescription) else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // (No error follows for an HTTP status: this is the only report.)
            send(.failed(download: download, piece: piece, resumeData: nil, message: "The server answered \(status)."))
            return
        }
        // Moved now: the system deletes `location` when this returns.
        let file = piecesDirectory.appending(path: "\(download)-\(piece)-\(UUID().uuidString).part")
        do {
            try FileManager.default.moveItem(at: location, to: file)
            send(.finished(download: download, piece: piece, file: file))
        } catch {
            send(.failed(download: download, piece: piece, resumeData: nil, message: "Couldn't keep the piece: \(error.localizedDescription)"))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let (download, piece) = Self.parse(task.taskDescription) else { return }
        let resume = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        TraceFile.write("downloads", "piece \(download)#\(piece) stopped: \(error.localizedDescription)\(resume == nil ? "" : " (resumable)")")
        send(.failed(download: download, piece: piece, resumeData: resume, message: error.localizedDescription))
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let done = backgroundCompletion.withLock { h -> (@Sendable () -> Void)? in defer { h = nil }; return h }
        DispatchQueue.main.async { done?() }
    }
}
