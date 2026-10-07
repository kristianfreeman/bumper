public import Foundation
import CloudKit

/// Your Jellyfin sign-in on your other devices: one record in your private
/// iCloud database (CloudKit), its contents in an end-to-end encrypted field
/// — sealed on the device, readable only on your devices. (iCloud Keychain
/// was the first try: tvOS never syncs its items.) A new Apple TV on the
/// account finds it at launch and signs itself in — with a sign-in of its
/// own, made by approving its own Quick Connect code with the shared one
/// (the server keys sessions by device: one token on two TVs made them one
/// device). Signing out anywhere takes it out, everywhere.
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

public actor CloudSignIns {
    public static let container = "iCloud.com.kristianfreeman.bumper"
    private static let recordID = CKRecord.ID(recordName: "signed-in")
    private let database: CKDatabase
    /// Why the last read or write failed (for the trace), or nil.
    public private(set) var lastError: String?

    public init(container: String = CloudSignIns.container) {
        database = CKContainer(identifier: container).privateCloudDatabase
    }

    /// Newest first; empty when there's none yet. nil when iCloud couldn't
    /// say (no account, no network, the container not ready): unknown is
    /// never "signed out" — a failed read once signed a TV out.
    public func load() async -> [CloudSignIn]? {
        do {
            let list = Self.decode(try await database.record(for: Self.recordID))
            lastError = nil
            return list
        } catch let error as CKError where error.code == .unknownItem {
            lastError = nil
            return []
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }

    /// Whether it's in iCloud now.
    @discardableResult
    public func upsert(_ entry: CloudSignIn) async -> Bool {
        await change { list in [entry] + list.filter { $0.key != entry.key } }
    }

    @discardableResult
    public func remove(serverId: String, userId: String) async -> Bool {
        await change { list in list.filter { $0.key != "\(serverId):\(userId)" } }
    }

    /// Read, change, write the one record (the newest write wins). A read
    /// that fails (other than "none yet") writes nothing: it would overwrite
    /// what it couldn't see.
    private func change(_ edit: ([CloudSignIn]) -> [CloudSignIn]) async -> Bool {
        let existing: CKRecord?
        do {
            existing = try await database.record(for: Self.recordID)
        } catch let error as CKError where error.code == .unknownItem {
            existing = nil
        } catch {
            lastError = String(describing: error)
            return false
        }
        let record = existing ?? CKRecord(recordType: "SignIns", recordID: Self.recordID)
        let list = edit(existing.map(Self.decode) ?? [])
        guard let data = try? JSONEncoder().encode(list) else { return false }
        record.encryptedValues["list"] = String(decoding: data, as: UTF8.self)
        do {
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            lastError = nil
            return true
        } catch {
            lastError = String(describing: error)
            return false
        }
    }

    private static func decode(_ record: CKRecord) -> [CloudSignIn] {
        guard let text = record.encryptedValues["list"] as? String,
              let list = try? JSONDecoder().decode([CloudSignIn].self, from: Data(text.utf8)) else { return [] }
        return list
    }
}
