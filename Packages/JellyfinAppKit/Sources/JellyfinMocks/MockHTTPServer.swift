public import Foundation
import Network
import Synchronization

/// The mock Jellyfin server on a real loopback socket (`http://127.0.0.1:<port>`).
///
/// URLProtocol interception covers URLSession, but AVPlayer and VLCKit do
/// their own networking — so to exercise both backends over a genuine TCP
/// stack the same router is served over HTTP/1.1 with keep-alive and Range
/// support.
public final class MockHTTPServer: Sendable {
    public static let shared = MockHTTPServer()

    public typealias Router = @Sendable (URLRequest) -> (Int, Data, [String: String])
    private let router: Router
    private let loopbackOnly: Bool

    /// Independent instances (tests use their own, on ephemeral ports).
    /// `router` defaults to the mock Jellyfin; `loopbackOnly: false` serves
    /// the LAN (scripts/mock-media-server: clips for a real Apple TV).
    public init(router: @escaping Router = MockJellyfinProtocol.route, loopbackOnly: Bool = true) {
        self.router = router
        self.loopbackOnly = loopbackOnly
    }

    private let listener = Mutex<NWListener?>(nil)
    /// Serialises start(): concurrent callers share one listener.
    private let startLock = NSLock()
    private let queue = DispatchQueue(label: "mock.http", qos: .userInitiated, attributes: .concurrent)

    private let boundPort = Atomic<UInt16>(0)
    public var port: UInt16 { boundPort.load(ordering: .relaxed) }

    public var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    /// Starts listening on an ephemeral loopback port; returns the base URL.
    @discardableResult
    public func start(port requested: UInt16 = 0) throws -> URL {
        startLock.lock()
        defer { startLock.unlock() }
        if let existing = listener.withLock({ $0 }), existing.state == .ready { return baseURL }
        let params = NWParameters.tcp
        if loopbackOnly { params.requiredInterfaceType = .loopback }
        params.allowLocalEndpointReuse = true
        let l = requested == 0
            ? try NWListener(using: params)
            : try NWListener(using: params, on: NWEndpoint.Port(rawValue: requested)!)
        let ready = DispatchSemaphore(value: 0)
        let failure = Mutex<NWError?>(nil)
        l.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let error): failure.withLock { $0 = error }; ready.signal()
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.serve(connection, buffer: Data())
        }
        l.start(queue: queue)
        // Never hand back a URL nobody is listening on.
        guard ready.wait(timeout: .now() + 5) == .success, l.state == .ready else {
            l.cancel()
            throw failure.withLock { $0 } ?? NWError.posix(.ETIMEDOUT)
        }
        boundPort.store(l.port?.rawValue ?? 0, ordering: .relaxed)
        listener.withLock { $0 = l }
        return baseURL
    }

    public func stop() {
        listener.withLock { $0?.cancel(); $0 = nil }
    }

    // MARK: HTTP/1.1

    private enum Parse {
        case complete(URLRequest, rest: Data)
        case incomplete
        case invalid
    }

    /// Requests already in the buffer are handled *before* reading more:
    /// a client may pipeline the next request in the same TCP segment as the
    /// previous body, and it will send nothing else until that is answered.
    private func serve(_ connection: NWConnection, buffer: Data) {
        switch parse(buffer) {
        case .complete(let request, let rest):
            respond(to: request, on: connection) { [weak self] in self?.serve(connection, buffer: rest) }
        case .invalid:
            connection.send(content: Data("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n".utf8), completion: .contentProcessed { _ in connection.cancel() })
        case .incomplete:
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data, !data.isEmpty { self.serve(connection, buffer: buffer + data) }
                else if isComplete || error != nil { connection.cancel() }
                else { self.serve(connection, buffer: buffer) }
            }
        }
    }

    private func parse(_ buffer: Data) -> Parse {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        // The body may arrive in later segments than the headers.
        let bodyLength = Int(headers["content-length"] ?? "0") ?? 0
        let afterHeaders = buffer[headerEnd.upperBound...]
        guard afterHeaders.count >= bodyLength else { return .incomplete }

        // Lenient: clients may send characters (|, spaces) URL(string:) rejects.
        let target = String(requestLine[1])
        guard let url = URL(string: "http://127.0.0.1:\(port)\(target)")
            ?? target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap({ URL(string: "http://127.0.0.1:\(port)\($0)") }) else { return .invalid }
        var request = URLRequest(url: url)
        request.httpMethod = String(requestLine[0])
        let body = afterHeaders.prefix(bodyLength)
        request.httpBody = body.isEmpty ? nil : Data(body)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        return .complete(request, rest: Data(afterHeaders.dropFirst(bodyLength)))
    }

    private func respond(to request: URLRequest, on connection: NWConnection, then next: @escaping @Sendable () -> Void) {
        let (status, payload, responseHeaders) = router(request)
        var head = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status).capitalized)\r\n"
        var allHeaders = responseHeaders
        allHeaders["Content-Length"] = String(payload.count)
        allHeaders["Connection"] = "keep-alive"
        for (k, v) in allHeaders { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        // Head and body as separate sends: large media bodies stay
        // memory-mapped slices instead of being copied into one buffer.
        let body = request.httpMethod == "HEAD" ? Data() : payload
        let send = {
            connection.send(content: Data(head.utf8), isComplete: false, completion: .contentProcessed { _ in })
            connection.send(content: body, completion: .contentProcessed { error in
                if error == nil { next() } else { connection.cancel() }
            })
        }
        let path = request.url?.path ?? ""
        let delay = MockMedia.latency.withLock { $0 }
        if delay > .zero, path.hasPrefix("/Videos") || path.hasPrefix("/Audio") {
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18) { send() }
        } else {
            send()
        }
    }
}
