import Foundation
import Security
import Synchronization

/// Access tokens live in the Keychain. On tvOS this is also the only storage
/// guaranteed to survive: the system may purge Caches *and* Application
/// Support when space is low.
public struct Keychain: Sendable {
    public let service: String
    /// iCloud Keychain: the item goes to this person's other devices
    /// (end-to-end encrypted; the same app on each reads it).
    public let synchronizable: Bool
    /// In-process tests: kept here instead, gone with the process (nothing
    /// written to the Mac's own Keychain, nothing for a test to find later).
    private let memory: Memory?

    public init(service: String = Brand.bundleIdentifier, synchronizable: Bool = false) {
        self.service = service
        self.synchronizable = synchronizable
        memory = nil
    }

    private init(memory: Memory) {
        service = "memory"
        synchronizable = false
        self.memory = memory
    }

    /// A Keychain of its own that only lives in memory (tests).
    public static func inMemory() -> Keychain { Keychain(memory: Memory()) }

    public func set(_ value: String, for account: String) {
        if let memory { memory.items.withLock { $0[account] = value }; return }
        let data = Data(value.utf8)
        let query = baseQuery(account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    public func get(_ account: String) -> String? {
        if let memory { return memory.items.withLock { $0[account] } }
        var query = baseQuery(account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard unsafe SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func remove(_ account: String) {
        if let memory { memory.items.withLock { $0[account] = nil }; return }
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private func baseQuery(_ account: String) -> [CFString: Any] {
        var q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        if synchronizable { q[kSecAttrSynchronizable] = kCFBooleanTrue }
        return q
    }

    private final class Memory: Sendable {
        let items = Mutex<[String: String]>([:])
    }
}
