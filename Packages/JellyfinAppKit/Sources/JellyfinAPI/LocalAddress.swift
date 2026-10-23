public import Foundation

extension URL {
    /// A server on this network (a .local name, a bare host name, a private
    /// address), as opposed to one reached over the internet.
    public var isOnLocalNetwork: Bool {
        guard let host = host()?.lowercased() else { return false }
        if host.hasSuffix(".local") || !host.contains(".") { return true }
        let p = host.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return false }
        return p[0] == 10 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && (16...31).contains(p[1])) || (p[0] == 169 && p[1] == 254)
    }
}
