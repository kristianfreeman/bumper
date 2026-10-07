import Foundation
import Network

/// macOS and iOS ask before an app reaches your home network — but only
/// when it goes looking. A server address alone didn't bring the question
/// up on the Mac (the request just failed as "offline"), so the app looks
/// for a moment at launch, which does.
enum LocalNetworkAccess {
    /// A short Bonjour look around: the system's question comes up, once.
    @MainActor static func ask() {
        let browser = NWBrowser(for: .bonjour(type: "_bumper._tcp", domain: nil), using: .tcp)
        browser.start(queue: .main)
        Task { try? await Task.sleep(for: .seconds(3)); browser.cancel() }
    }

    /// A server on this network (a private address, a .local name, a bare
    /// host name): the kind Local Network access is for.
    static func isLocal(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        if host.hasSuffix(".local") || !host.contains(".") { return true }
        let p = host.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return false }
        return p[0] == 10 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && (16...31).contains(p[1])) || (p[0] == 169 && p[1] == 254)
    }

    /// Settings → Privacy & Security → Local Network (the Mac); this app's
    /// own page in Settings (iPhone, iPad).
    static var settingsURL: URL? {
        #if os(macOS)
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")
        #elseif os(iOS)
        URL(string: "app-settings:")
        #else
        nil
        #endif
    }
}
