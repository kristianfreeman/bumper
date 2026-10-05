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
    /// Every way we have: the broadcast, and on iPhone/iPad (where a
    /// broadcast needs Apple's multicast entitlement) a look at each address
    /// on the local subnet too.
    @concurrent
    public static func discoverAll() async -> [DiscoveredServer] {
        async let broadcast = discover()
        #if os(iOS)
        async let scanned = scanSubnet()
        let all = await broadcast + scanned
        #else
        let all = await broadcast
        #endif
        var byId: [String: DiscoveredServer] = [:]
        for s in all where byId[s.id] == nil { byId[s.id] = s }
        return byId.values.sorted { $0.name < $1.name }
    }

    /// Asks each address on this device's IPv4 subnet (up to a /24) for
    /// Jellyfin's public info on `port`. Unicast, so it works without the
    /// multicast entitlement; ~254 short requests, 64 at a time (≈2 s).
    @concurrent
    public static func scanSubnet(port: Int = 8096, timeout: Double = 0.5) async -> [DiscoveredServer] {
        guard let (address, mask) = localIPv4() else { return [] }
        let hostBits = 32 - mask.nonzeroBitCount
        guard hostBits > 0, hostBits <= 8 else { return [] }
        let network = address & mask
        let hosts = (1..<(1 << hostBits) - 1).map { network | UInt32($0) }.filter { $0 != address }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        struct Info: Decodable { let Id: String?; let ServerName: String? }
        return await withTaskGroup(of: DiscoveredServer?.self) { group in
            var found: [DiscoveredServer] = []
            var next = hosts.makeIterator()
            func add() -> Bool {
                guard let host = next.next() else { return false }
                let ip = "\(host >> 24).\((host >> 16) & 0xff).\((host >> 8) & 0xff).\(host & 0xff)"
                group.addTask {
                    let base = "http://\(ip):\(port)"
                    guard let url = URL(string: base + "/System/Info/Public"),
                          let (data, response) = try? await session.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200,
                          let info = try? JSONDecoder().decode(Info.self, from: data), let id = info.Id else { return nil }
                    return DiscoveredServer(id: id, name: info.ServerName ?? ip, address: base)
                }
                return true
            }
            for _ in 0..<64 { if !add() { break } }
            while let result = await group.next() {
                if let result { found.append(result) }
                _ = add()
            }
            return found
        }
    }

    /// This device's Wi-Fi/Ethernet IPv4 address and netmask (host order).
    static func localIPv4() -> (UInt32, UInt32)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard unsafe getifaddrs(&list) == 0, let first = unsafe list else { return nil }
        defer { unsafe freeifaddrs(list) }
        var best: (UInt32, UInt32)?
        for unsafe ptr in unsafe sequence(first: first, next: { unsafe $0.pointee.ifa_next }) {
            let ifa = unsafe ptr.pointee
            guard let sa = unsafe ifa.ifa_addr, unsafe sa.pointee.sa_family == UInt8(AF_INET), let nm = unsafe ifa.ifa_netmask else { continue }
            let name = unsafe String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }               // Wi-Fi / Ethernet, not cellular or VPN
            let addr = unsafe sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { unsafe $0.pointee.sin_addr.s_addr }
            let mask = unsafe nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { unsafe $0.pointee.sin_addr.s_addr }
            let a = UInt32(bigEndian: addr), m = UInt32(bigEndian: mask)
            if a != 0, best == nil || name == "en0" { best = (a, m) }
        }
        return best
    }

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
