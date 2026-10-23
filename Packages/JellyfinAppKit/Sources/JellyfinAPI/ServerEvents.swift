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

    /// Each time the server says a library changed (something added,
    /// removed, its details refreshed), until the connection drops: the
    /// caller opens it again. The server asks to be kept alive
    /// (`ForceKeepAlive`, with how often); this does that.
    public func libraryChanges() -> AsyncStream<Void> {
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
                    guard let message = try? await socket.receive() else { return }
                    let data: Data? = switch message {
                    case .string(let s): Data(s.utf8)
                    case .data(let d): d
                    @unknown default: nil
                    }
                    guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = json["MessageType"] as? String else { continue }
                    switch type {
                    case "ForceKeepAlive":
                        let every = max(5, ((json["Data"] as? Double) ?? 60) / 2)
                        keepAlive?.cancel()
                        keepAlive = Task {
                            while !Task.isCancelled {
                                try? await socket.send(.string(#"{"MessageType":"KeepAlive"}"#))
                                try? await Task.sleep(for: .seconds(every))
                            }
                        }
                    case "LibraryChanged":
                        continuation.yield()
                    default:
                        break
                    }
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
    }
}
