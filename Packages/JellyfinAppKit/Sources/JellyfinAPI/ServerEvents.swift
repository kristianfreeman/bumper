public import Foundation

// MARK: - The server's news (Jellyfin's WebSocket)

extension JellyfinClient {
    /// `/socket`, signed in: where the server says what's changing as it happens.
    public var socketURL: URL {
        var c = URLComponents(url: url("/socket", query: [.init(name: "api_key", value: accessToken), .init(name: "deviceId", value: clientInfo.deviceId)]),
                              resolvingAgainstBaseURL: false)!
        c.scheme = c.scheme == "https" ? "wss" : "ws"
        return c.url!
    }

    /// What the server announced.
    public enum ServerChange: Sendable {
        /// Something added, removed, or its details refreshed.
        case library
        /// Watched, a resume point, a favourite — here or on another device.
        case userData
        /// Connected (the server asked to be kept alive), for the trace.
        case connected
        /// Dropped, and why.
        case dropped(String)
    }

    /// The server's announcements, until the connection drops: the caller
    /// opens it again. The server asks to be kept alive (`ForceKeepAlive`,
    /// with how often); this does that.
    public func serverChanges() -> AsyncStream<ServerChange> {
        let socket = URLSession.shared.webSocketTask(with: socketURL)
        return AsyncStream { continuation in
            socket.resume()
            let reader = Task {
                var keepAlive: Task<Void, Never>?
                defer {
                    keepAlive?.cancel()
                    socket.cancel(with: .goingAway, reason: nil)
                    continuation.finish()
                }
                while !Task.isCancelled {
                    let message: URLSessionWebSocketTask.Message
                    do { message = try await socket.receive() } catch {
                        continuation.yield(.dropped(error.localizedDescription))
                        return
                    }
                    let data: Data? = switch message {
                    case .string(let s): Data(s.utf8)
                    case .data(let d): d
                    @unknown default: nil
                    }
                    guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = json["MessageType"] as? String else { continue }
                    switch type {
                    case "ForceKeepAlive":
                        if keepAlive == nil { continuation.yield(.connected) }
                        let every = max(5, ((json["Data"] as? Double) ?? 60) / 2)
                        keepAlive?.cancel()
                        keepAlive = Task {
                            while !Task.isCancelled {
                                try? await socket.send(.string(#"{"MessageType":"KeepAlive"}"#))
                                try? await Task.sleep(for: .seconds(every))
                            }
                        }
                    case "LibraryChanged":
                        continuation.yield(.library)
                    case "UserDataChanged":
                        continuation.yield(.userData)
                    default:
                        break
                    }
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
    }
}
