public import Foundation

/// Your Jellyfin sign-in on your other devices, through iCloud Keychain
/// (end-to-end encrypted; only this app on your devices reads it). A new
/// Apple TV on the account finds it at launch and signs itself in — with a
/// sign-in of its own, made by approving its own Quick Connect code with the
/// shared one (the server keys sessions by device: one token on two TVs made
/// them one device). Signing out anywhere takes it out, everywhere.
public struct CloudSignIn: Codable, Sendable, Equatable {
    public var server: ServerRecord
    public var account: AccountRecord
    public var token: String

    public init(server: ServerRecord, account: AccountRecord, token: String) {
        self.server = server
        self.account = account
        self.token = token
    }

    /// The person on the server (the account's id, without the device).
    public var key: String { "\(server.id):\(account.userId)" }
}

public struct CloudSignIns: Sendable {
    private let keychain: Keychain
    private static let item = "signed-in"

    public init(service: String = Brand.bundleIdentifier + ".cloud") {
        keychain = Keychain(service: service, synchronizable: true)
    }

    /// Newest first.
    public func load() -> [CloudSignIn] {
        guard let text = keychain.get(Self.item), let list = try? JSONDecoder().decode([CloudSignIn].self, from: Data(text.utf8)) else { return [] }
        return list
    }

    public func upsert(_ entry: CloudSignIn) {
        save([entry] + load().filter { $0.key != entry.key })
    }

    public func remove(serverId: String, userId: String) {
        save(load().filter { $0.key != "\(serverId):\(userId)" })
    }

    private func save(_ list: [CloudSignIn]) {
        guard let data = try? JSONEncoder().encode(list), let text = String(data: data, encoding: .utf8) else { return }
        keychain.set(text, for: Self.item)
    }
}
