public import Foundation
import Instrumentation
import os

/// Identifies this app to the Jellyfin server. Sent on every request as the
/// `Authorization: MediaBrowser …` header (the modern replacement for
/// `X-Emby-Authorization`).
public struct ClientInfo: Sendable, Hashable, Codable {
    public var client: String
    public var device: String
    public var deviceId: String
    public var version: String

    public init(client: String, device: String, deviceId: String, version: String) {
        self.client = client
        self.device = device
        self.deviceId = deviceId
        self.version = version
    }

    func authorizationHeader(token: String?) -> String {
        /// Plain ASCII: header values can't carry "Kristian’s MacBook Pro"'s
        /// curly apostrophe (the server answered 400 to every request).
        func esc(_ s: String) -> String {
            let folded = s.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
                .replacingOccurrences(of: "“", with: "'").replacingOccurrences(of: "”", with: "'")
                .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
                .replacingOccurrences(of: "\"", with: "'")
            return String(String.UnicodeScalarView(folded.unicodeScalars.filter { $0.isASCII && $0.value >= 32 }))
        }
        var parts = [
            "Client=\"\(esc(client))\"",
            "Device=\"\(esc(device))\"",
            "DeviceId=\"\(esc(deviceId))\"",
            "Version=\"\(esc(version))\"",
        ]
        if let token { parts.append("Token=\"\(token)\"") }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }
}

public enum JellyfinError: Error, Sendable, Equatable, LocalizedError {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case server(status: Int, message: String?)
    case decoding(String)
    case transport(String)
    case unsupportedServer(version: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "That doesn't look like a valid server address."
        case .unauthorized: "You've been signed out. Sign in again."
        case .forbidden: "You don't have permission to do that."
        case .notFound: "Not found on the server."
        case .server(let status, let message): message ?? "Server error (\(status))."
        case .decoding(let detail): "The server sent something unexpected. \(detail)"
        case .transport(let detail): detail
        case .unsupportedServer(let v): "This server runs Jellyfin \(v). It needs 10.10 or newer."
        }
    }
}

/// A typed request. `Response == Void` requests ignore the body.
public struct Request<Response: Sendable>: Sendable {
    public enum Method: String, Sendable { case get = "GET", post = "POST", delete = "DELETE" }

    public var method: Method
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?
    public var timeout: TimeInterval?
    let decode: @Sendable (Data, JSONDecoder) throws -> Response

    public init(
        _ method: Method = .get,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        timeout: TimeInterval? = nil,
        decode: @escaping @Sendable (Data, JSONDecoder) throws -> Response
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.timeout = timeout
        self.decode = decode
    }
}

extension Request where Response: Decodable {
    public init(_ method: Method = .get, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, timeout: TimeInterval? = nil) {
        self.init(method, path, query: query, body: body, timeout: timeout) { data, decoder in
            try decoder.decode(Response.self, from: data)
        }
    }
}

extension Request where Response == Void {
    public init(_ method: Method = .post, _ path: String, query: [URLQueryItem] = [], body: Data? = nil) {
        self.init(method, path, query: query, body: body, timeout: nil) { _, _ in () }
    }
}

/// A Jellyfin API client bound to one server and (optionally) one user session.
///
/// Immutable and `Sendable`: signing in produces a *new* client via
/// `authenticated(token:userId:)`, so there is never shared mutable auth state.
public final class JellyfinClient: Sendable {
    public let baseURL: URL
    public let clientInfo: ClientInfo
    public let accessToken: String?
    public let userId: String?
    public let session: URLSession

    private static let log = Perf.logger("api")

    public init(baseURL: URL, clientInfo: ClientInfo, accessToken: String? = nil, userId: String? = nil, session: URLSession = JellyfinClient.makeSession()) {
        self.baseURL = baseURL
        self.clientInfo = clientInfo
        self.accessToken = accessToken
        self.userId = userId
        self.session = session
    }

    public func authenticated(token: String, userId: String) -> JellyfinClient {
        JellyfinClient(baseURL: baseURL, clientInfo: clientInfo, accessToken: token, userId: userId, session: session)
    }

    /// Tuned for a TV on a LAN: aggressive connection reuse, short timeouts so a
    /// dead server fails fast instead of spinning, HTTP/2+ when the reverse
    /// proxy supports it.
    public static func makeSession(protocolClasses: [AnyClass] = []) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpAdditionalHeaders = ["Accept": "application/json", "Accept-Encoding": "gzip, br"]
        if !protocolClasses.isEmpty {
            config.protocolClasses = protocolClasses + (config.protocolClasses ?? [])
        }
        return URLSession(configuration: config)
    }

    public var authorizationHeader: String { clientInfo.authorizationHeader(token: accessToken) }

    /// Builds an absolute URL for a server path (used for streams & images,
    /// which go to AVFoundation / the image pipeline rather than `send`).
    public func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + (path.hasPrefix("/") ? path : "/" + path)
        let filtered = query.filter { $0.value != nil }
        components.queryItems = filtered.isEmpty ? nil : filtered
        // `+` is legal in query strings but Jellyfin (ASP.NET) decodes it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    func urlRequest<R>(for request: Request<R>) -> URLRequest {
        var urlRequest = URLRequest(url: url(request.path, query: request.query))
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let timeout = request.timeout { urlRequest.timeoutInterval = timeout }
        return urlRequest
    }

    public func send<R>(_ request: Request<R>) async throws -> R {
        let urlRequest = urlRequest(for: request)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Perf.measure("api.request", .apiRequest) {
                try await session.data(for: urlRequest)
            }
        } catch let error as URLError {
            Self.log.error("\(request.method.rawValue) \(request.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw JellyfinError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw JellyfinError.transport("No HTTP response") }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw JellyfinError.unauthorized
        case 403: throw JellyfinError.forbidden
        case 404: throw JellyfinError.notFound
        default:
            throw JellyfinError.server(status: http.statusCode, message: String(data: data.prefix(512), encoding: .utf8))
        }

        do {
            return try Perf.measureSync("api.decode", .apiDecode) {
                try request.decode(data, JSONDecoder.jellyfin)
            }
        } catch let error as DecodingError {
            Self.log.error("Decoding \(request.path, privacy: .public): \(String(describing: error), privacy: .public)")
            throw JellyfinError.decoding(error.shortDescription)
        }
    }
}

extension JSONDecoder {
    /// Shared decoder. Every model declares explicit PascalCase `CodingKeys`,
    /// which is markedly faster than a `.custom` key strategy (no per-key
    /// closure call + string allocation).
    public static var jellyfin: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = JellyfinDate.parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(string)")
        }
        return decoder
    }
}

extension JSONEncoder {
    public static let jellyfin: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

/// Jellyfin emits ISO-8601 with 7 fractional digits ("2024-01-02T03:04:05.1234567Z"),
/// which `ISO8601DateFormatter` rejects. Parse the fast way.
enum JellyfinDate {
    static func parse(_ s: String) -> Date? {
        var trimmed = Substring(s)
        if let dot = trimmed.firstIndex(of: ".") {
            let tzStart = trimmed[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) ?? trimmed.endIndex
            let fraction = trimmed[trimmed.index(after: dot)..<tzStart]
            let fracSeconds = Double("0." + fraction) ?? 0
            let base = String(trimmed[..<dot]) + String(trimmed[tzStart...])
            guard let date = parseWhole(base) else { return nil }
            return date.addingTimeInterval(fracSeconds)
        }
        trimmed = Substring(s)
        return parseWhole(String(trimmed))
    }

    private static func parseWhole(_ s: String) -> Date? {
        var str = s
        if !(str.hasSuffix("Z") || str.dropFirst(19).contains("+") || str.dropFirst(19).contains("-")) {
            str += "Z"
        }
        return try? Date(str, strategy: .iso8601)
    }
}

extension DecodingError {
    var shortDescription: String {
        switch self {
        case .keyNotFound(let key, let ctx): "Missing \(key.stringValue) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx), .dataCorrupted(let ctx):
            "\(ctx.debugDescription) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default: "\(self)"
        }
    }
}
