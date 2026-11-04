import Foundation
import Instrumentation
import Network
import PlaybackCore

/// MKVs VLCKit can't seek in, served to it with their SeekHead in order.
///
/// An MKV whose SeekHead lists the Cues before the Tracks can't be seeked in
/// by VLCKit (see `MatroskaSeekHead`): Dark City couldn't resume at 2 min.
/// The fix is a few bytes at the start of the file, so the file plays from
/// here instead: `http://127.0.0.1:<port>/…` passes each range VLCKit asks
/// for through from the server and swaps those bytes as they go by. VLCKit's
/// own HTTP (prefetch, caching, reconnects) is untouched, and the server only
/// sends the file, as before — no conversion (a NAS that can't transcode).
final class SeekHeadProxy: @unchecked Sendable {
    static let shared = SeekHeadProxy()

    /// Everything below runs on this queue: the listener, its connections
    /// and URLSession's callbacks.
    private let queue = DispatchQueue(label: "mkv.seekhead.proxy", qos: .userInitiated)
    private var listener: NWListener?
    private var port: UInt16 = 0
    private var files: [String: (upstream: URL, fix: MatroskaSeekHead.Fix)] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        let delegates = OperationQueue()
        delegates.underlyingQueue = queue
        delegates.maxConcurrentOperationCount = 1
        return URLSession(configuration: config, delegate: nil, delegateQueue: delegates)
    }()

    /// What VLCKit opens for `upstream`, served with `fix`.
    func url(for upstream: URL, fix: MatroskaSeekHead.Fix) throws -> URL {
        try queue.sync {
            try startIfNeeded()
            let path = "/\(UUID().uuidString).\(upstream.pathExtension.isEmpty ? "mkv" : upstream.pathExtension)"
            files[path] = (upstream, fix)
            return URL(string: "http://127.0.0.1:\(port)\(path)")!
        }
    }

    private func startIfNeeded() throws {
        if let listener, listener.state == .ready { return }
        listener?.cancel()
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params)
        let ready = DispatchSemaphore(value: 0)
        l.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
            if case .failed = state { ready.signal() }
        }
        l.newConnectionHandler = { [unowned self] connection in
            queue.async { [unowned self] in
                connection.start(queue: queue)
                readRequest(on: connection, buffer: Data())
            }
        }
        // Its own queue to come up on: this one is waiting for it.
        l.start(queue: DispatchQueue(label: "mkv.seekhead.listener"))
        guard ready.wait(timeout: .now() + 3) == .success, l.state == .ready, let p = l.port?.rawValue else {
            l.cancel()
            throw URLError(.cannotConnectToHost)
        }
        listener = l
        port = p
        TraceFile.write("vlc", "MKV proxy on 127.0.0.1:\(p)")
    }

    // MARK: Which files

    /// Files already looked at (the server's path, without the query): the
    /// fix, or none. A reopen or a second play doesn't ask again.
    private var checked: [String: MatroskaSeekHead.Fix?] = [:]

    /// The URL VLCKit should open for an MKV at `upstream`: the proxy's, when
    /// the file needs its SeekHead fixed; else `upstream` itself. One small
    /// read of the file's start (4 KB, once per file); if that fails, the
    /// file plays as it is.
    func served(_ upstream: URL) async -> URL {
        let key = upstream.path()
        let known = queue.sync { checked[key] }
        let fix: MatroskaSeekHead.Fix?
        if let known { fix = known } else {
            var request = URLRequest(url: upstream, timeoutInterval: 5)
            request.setValue("bytes=0-\(MatroskaSeekHead.headLength - 1)", forHTTPHeaderField: "Range")
            guard let (head, _) = try? await URLSession.shared.data(for: request) else { return upstream }
            fix = MatroskaSeekHead.fix(head: head)
            queue.sync { checked[key] = .some(fix) }
        }
        guard let fix, let url = try? url(for: upstream, fix: fix) else { return upstream }
        TraceFile.write("vlc", "MKV lists its index before its tracks (VLCKit couldn't seek): served with them in order, through 127.0.0.1")
        return url
    }

    // MARK: One request per connection

    private func readRequest(on connection: NWConnection, buffer: Data) {
        if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
            let lines = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            let parts = lines.first?.split(separator: " ") ?? []
            let range = lines.dropFirst().first { $0.lowercased().hasPrefix("range:") }
                .map { String($0.dropFirst("range:".count)).trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, let file = files[String(parts[1].split(separator: "?").first ?? "")] else {
                finish(connection, status: "404 Not Found")
                return
            }
            Relay(connection: connection, file: file, method: String(parts[0]), range: range, session: session).start()
            return
        }
        guard buffer.count < 16 * 1024 else { finish(connection, status: "400 Bad Request"); return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [unowned self] data, _, done, error in
            if let data, !data.isEmpty { readRequest(on: connection, buffer: buffer + data) }
            else if done || error != nil { connection.cancel() }
        }
    }

    private func finish(_ connection: NWConnection, status: String) {
        connection.send(content: Data("HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    /// One range of the file, from the server to VLCKit, fixed on the way.
    /// It reads only a few MB ahead of what VLCKit has taken: a 4K remux at
    /// 80 Mb/s doesn't pile up in memory.
    private final class Relay: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let connection: NWConnection
        let file: (upstream: URL, fix: MatroskaSeekHead.Fix)
        let method: String
        let range: String?
        let session: URLSession
        var task: URLSessionDataTask?
        var offset = 0                     // the file position of the next byte to VLCKit
        var inFlight = 0
        var held = false
        var answered = false

        init(connection: NWConnection, file: (upstream: URL, fix: MatroskaSeekHead.Fix), method: String, range: String?, session: URLSession) {
            self.connection = connection
            self.file = file
            self.method = method
            self.range = range
            self.session = session
        }

        func start() {
            var request = URLRequest(url: file.upstream)
            request.httpMethod = method == "HEAD" ? "HEAD" : "GET"
            if let range { request.setValue(range, forHTTPHeaderField: "Range") }
            let task = session.dataTask(with: request)
            task.delegate = self
            self.task = task
            // VLCKit hung up (a seek opens a new one): stop reading for it.
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .cancelled: self?.task?.cancel()
                default: break
                }
            }
            task.resume()
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
            guard let http = response as? HTTPURLResponse else { return .cancel }
            answered = true
            var head = "HTTP/1.1 \(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode).capitalized)\r\n"
            for name in ["Content-Length", "Content-Range", "Content-Type", "Accept-Ranges", "Last-Modified", "ETag"] {
                if let value = http.value(forHTTPHeaderField: name) { head += "\(name): \(value)\r\n" }
            }
            head += "Connection: close\r\n\r\n"
            // "bytes 1234-5678/9999": where this range starts in the file.
            if let r = http.value(forHTTPHeaderField: "Content-Range"),
               let first = r.split(separator: " ").last?.split(separator: "-").first, let start = Int(first) {
                offset = start
            }
            connection.send(content: Data(head.utf8), completion: .idempotent)
            return .allow
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            var chunk = data
            MatroskaSeekHead.apply(file.fix, to: &chunk, at: offset)
            offset += chunk.count
            inFlight += chunk.count
            if inFlight > 8 << 20, !held { held = true; dataTask.suspend() }
            connection.send(content: chunk, completion: .contentProcessed { [weak self] _ in
                guard let self else { return }
                inFlight -= chunk.count
                if held, inFlight < 2 << 20 { held = false; task?.resume() }
            })
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            if !answered {
                connection.send(content: Data("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), completion: .idempotent)
            }
            // After everything queued before it has gone out.
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [connection] _ in
                connection.cancel()
            })
        }
    }
}
