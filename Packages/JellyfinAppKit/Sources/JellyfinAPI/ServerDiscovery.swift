import Foundation
import Darwin

/// LAN auto-discovery: Jellyfin answers a UDP broadcast of
/// "Who is JellyfinServer?" on port 7359 with a small JSON blob.
public struct DiscoveredServer: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var address: String

    enum CodingKeys: String, CodingKey { case id = "Id", name = "Name", address = "Address" }

    public init(id: String, name: String, address: String) {
        self.id = id
        self.name = name
        self.address = address
    }
}

public enum ServerDiscovery {
    /// Broadcasts once and collects replies for `timeout`. Runs on a
    /// background thread; never blocks the caller's actor.
    @concurrent
    public static func discover(timeout: Duration = .seconds(2)) async -> [DiscoveredServer] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var yes: Int32 = 1
        unsafe setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 0, tv_usec: 250_000)
        unsafe setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(7359).bigEndian
        addr.sin_addr.s_addr = INADDR_BROADCAST

        let message = Array("Who is JellyfinServer?".utf8)
        let sent = withUnsafePointer(to: &addr) { ptr in
            unsafe ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                unsafe sendto(fd, message, message.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent > 0 else { return [] }

        var found: [String: DiscoveredServer] = [:]
        let deadline = ContinuousClock.now + timeout
        var buffer = [UInt8](repeating: 0, count: 4096)
        while ContinuousClock.now < deadline, !Task.isCancelled {
            let n = unsafe recv(fd, &buffer, buffer.count, 0)
            guard n > 0 else { continue }
            if let server = try? JSONDecoder().decode(DiscoveredServer.self, from: Data(buffer[0..<n])) {
                found[server.id] = server
            }
        }
        return found.values.sorted { $0.name < $1.name }
    }
}
