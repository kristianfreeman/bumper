public import Foundation
#if os(iOS)
import UIKit
#endif
public import JellyfinAPI
public import Observation

public struct ServerRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var url: URL
    public var version: String?

    public init(id: String, name: String, url: URL, version: String?) {
        self.id = id
        self.name = name
        self.url = url
        self.version = version
    }
}

public struct AccountRecord: Codable, Identifiable, Hashable, Sendable {
    public var serverId: String
    public var userId: String
    public var userName: String
    public var imageTag: String?
    public var lastUsed: Date

    public var id: String { "\(serverId):\(userId)" }

    public init(serverId: String, userId: String, userName: String, imageTag: String?, lastUsed: Date = .now) {
        self.serverId = serverId
        self.userId = userId
        self.userName = userName
        self.imageTag = imageTag
        self.lastUsed = lastUsed
    }
}

/// A signed-in user on a server, with a ready-to-use API client.
public struct UserSession: Sendable, Identifiable {
    public let server: ServerRecord
    public let account: AccountRecord
    public let client: JellyfinClient

    public var id: String { account.id }

    public init(server: ServerRecord, account: AccountRecord, client: JellyfinClient) {
        self.server = server
        self.account = account
        self.client = client
    }
}

/// Persists known servers and signed-in accounts. Metadata goes to
/// UserDefaults (small, persistent on tvOS); tokens go to the Keychain.
@MainActor
@Observable
public final class AccountStore {
    public private(set) var servers: [ServerRecord] = []
    public private(set) var accounts: [AccountRecord] = []
    public private(set) var activeAccountId: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: Keychain
    @ObservationIgnored private let protocolClasses: [AnyClass]
    @ObservationIgnored private var sessions: [String: URLSession] = [:]
    /// Your sign-ins on your other devices (CloudKit); nil in tests.
    @ObservationIgnored public var cloud: CloudSignIns?

    private enum Keys {
        static let servers = "accounts.servers"
        static let accounts = "accounts.accounts"
        static let active = "accounts.active"
        static let deviceId = "device.id"
    }

    /// - Parameter protocolClasses: injected URLProtocols (the mock server in UI tests).
    public init(defaults: UserDefaults = .standard, keychain: Keychain = Keychain(), protocolClasses: [AnyClass] = []) {
        self.defaults = defaults
        self.keychain = keychain
        self.protocolClasses = protocolClasses
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: Keys.servers), let s = try? decoder.decode([ServerRecord].self, from: data) { servers = s }
        if let data = defaults.data(forKey: Keys.accounts), let a = try? decoder.decode([AccountRecord].self, from: data) { accounts = a }
        activeAccountId = defaults.string(forKey: Keys.active)
    }

    // MARK: Device identity

    /// Stable per-install identifier. Jellyfin keys sessions by DeviceId, so
    /// each *user* gets a derived id (otherwise signing in a second user on the
    /// same TV kicks the first one's session).
    public var baseDeviceId: String {
        if let id = keychain.get(Keys.deviceId) { return id }
        let id = UUID().uuidString
        keychain.set(id, for: Keys.deviceId)
        return id
    }

    public func clientInfo(forUser userId: String?) -> ClientInfo {
        let base = baseDeviceId
        let deviceId = userId.map { "\(base)-\($0.prefix(8))" } ?? base
        return ClientInfo(client: Brand.displayName, device: deviceName, deviceId: deviceId, version: Brand.version)
    }

    private var deviceName: String {
        #if os(tvOS)
        "Apple TV"
        #elseif os(iOS)
        // The model ("iPhone", "iPad"): the user's own device name needs an entitlement.
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        Host.current().localizedName ?? "Mac"
        #endif
    }

    private func urlSession(for serverId: String) -> URLSession {
        if let s = sessions[serverId] { return s }
        let s = JellyfinClient.makeSession(protocolClasses: protocolClasses)
        sessions[serverId] = s
        return s
    }

    // MARK: Clients

    /// Unauthenticated client for probing / signing in to a server.
    public func anonymousClient(for url: URL) -> JellyfinClient {
        JellyfinClient(baseURL: url, clientInfo: clientInfo(forUser: nil), session: JellyfinClient.makeSession(protocolClasses: protocolClasses))
    }

    /// A client for signing in with Quick Connect / password, using the
    /// per-user device id once we know who the user is.
    public func client(for server: ServerRecord, userId: String? = nil) -> JellyfinClient {
        JellyfinClient(baseURL: server.url, clientInfo: clientInfo(forUser: userId), session: urlSession(for: server.id))
    }

    // MARK: Mutations

    public func upsert(server: ServerRecord) {
        servers.removeAll { $0.id == server.id }
        servers.insert(server, at: 0)
        persist()
    }

    /// Records a successful sign-in and makes it the active account.
    @discardableResult
    public func signIn(server: ServerRecord, result: AuthenticationResult) -> UserSession {
        upsert(server: server)
        let account = AccountRecord(serverId: server.id, userId: result.user.id, userName: result.user.name ?? "User", imageTag: result.user.primaryImageTag)
        accounts.removeAll { $0.id == account.id }
        accounts.insert(account, at: 0)
        keychain.set(result.accessToken, for: tokenKey(account.id))
        activeAccountId = account.id
        persist()
        if let cloud {
            let entry = CloudSignIn(server: server, account: account, token: result.accessToken)
            Task { if await cloud.upsert(entry) { self.markSeenInCloud(account.id) } }
        }
        return session(for: account, token: result.accessToken, server: server)
    }

    /// Signed in with another device's token (its server has Quick Connect
    /// off): the same sign-in, shared.
    @discardableResult
    public func adopt(_ entry: CloudSignIn) -> UserSession {
        upsert(server: entry.server)
        var account = entry.account
        account.lastUsed = .now
        accounts.removeAll { $0.id == account.id }
        accounts.insert(account, at: 0)
        keychain.set(entry.token, for: tokenKey(account.id))
        activeAccountId = account.id
        persist()
        markSeenInCloud(account.id)                                     // it came from iCloud
        return session(for: account, token: entry.token, server: entry.server)
    }

    /// Signed out on another device: the account was in iCloud (`list`, just
    /// read), and isn't now.
    public func signedOutElsewhere(_ list: [CloudSignIn]) -> Bool {
        guard cloud != nil, let id = activeAccountId, let account = accounts.first(where: { $0.id == id }),
              defaults.bool(forKey: "cloud.seen.v2.\(id)") else { return false }
        return !list.contains { $0.server.id == account.serverId && $0.account.userId == account.userId }
    }

    /// Signed in before iCloud sign-in existed: put it there for the others.
    public func shareActive(_ list: [CloudSignIn]) async {
        guard let cloud, let id = activeAccountId, let account = accounts.first(where: { $0.id == id }),
              let server = servers.first(where: { $0.id == account.serverId }), let token = keychain.get(tokenKey(id)) else { return }
        let there = list.contains(where: { $0.server.id == server.id && $0.account.userId == account.userId })
        if there { markSeenInCloud(id) }
        else if await cloud.upsert(CloudSignIn(server: server, account: account, token: token)) { markSeenInCloud(id) }
    }

    /// Only once it's really in iCloud: then its going means signed out elsewhere.
    private func markSeenInCloud(_ accountId: String) { defaults.set(true, forKey: "cloud.seen.v2.\(accountId)") }

    /// The server's current name and picture for an account (they change
    /// there: a new profile picture has a new tag). Returns whether it changed.
    @discardableResult
    public func updateProfile(_ accountId: String, name: String?, imageTag: String?) -> Bool {
        guard let i = accounts.firstIndex(where: { $0.id == accountId }) else { return false }
        let name = name ?? accounts[i].userName
        guard accounts[i].userName != name || accounts[i].imageTag != imageTag else { return false }
        accounts[i].userName = name
        accounts[i].imageTag = imageTag
        persist()
        return true
    }

    public func signOut(_ accountId: String) {
        if let account = accounts.first(where: { $0.id == accountId }) {
            if let cloud { Task { await cloud.remove(serverId: account.serverId, userId: account.userId) } }   // everywhere
        }
        defaults.removeObject(forKey: "cloud.seen.v2.\(accountId)")
        accounts.removeAll { $0.id == accountId }
        keychain.remove(tokenKey(accountId))
        if activeAccountId == accountId { activeAccountId = nil }
        persist()
    }

    public func switchTo(_ accountId: String) -> UserSession? {
        guard var account = accounts.first(where: { $0.id == accountId }) else { return nil }
        account.lastUsed = .now
        accounts.removeAll { $0.id == accountId }
        accounts.insert(account, at: 0)
        activeAccountId = accountId
        persist()
        return restoreActiveSession()
    }

    /// Rebuilds the last session synchronously at launch: no network needed,
    /// so the home screen can render from cache immediately.
    public func restoreActiveSession() -> UserSession? {
        guard let id = activeAccountId,
              let account = accounts.first(where: { $0.id == id }),
              let server = servers.first(where: { $0.id == account.serverId }),
              let token = keychain.get(tokenKey(id)) else { return nil }
        return session(for: account, token: token, server: server)
    }

    private func session(for account: AccountRecord, token: String, server: ServerRecord) -> UserSession {
        let client = client(for: server, userId: account.userId).authenticated(token: token, userId: account.userId)
        return UserSession(server: server, account: account, client: client)
    }

    private func tokenKey(_ accountId: String) -> String { "token.\(accountId)" }

    private func persist() {
        let encoder = JSONEncoder()
        defaults.set(try? encoder.encode(servers), forKey: Keys.servers)
        defaults.set(try? encoder.encode(accounts), forKey: Keys.accounts)
        defaults.set(activeAccountId, forKey: Keys.active)
    }
}
