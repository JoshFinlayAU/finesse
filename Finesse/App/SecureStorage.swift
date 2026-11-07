import Foundation
import Security

/// Small secrets that must outlive purged caches.
protocol SecureStorage: Sendable {
    func data(for account: String) throws -> Data?
    func set(_ data: Data, for account: String) throws
    func remove(_ account: String) throws
}

struct KeychainError: Error, Equatable {
    let status: OSStatus
}

struct KeychainStorage: SecureStorage {
    let service: String
    /// Nil is the app's own default group, where the accounts have always been.
    var accessGroup: String?

    private func query(_ account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    func data(for account: String) throws -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return result as? Data
    }

    func set(_ data: Data, for account: String) throws {
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(query(account) as CFDictionary, update)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }

        var item = query(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    func remove(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

/// Everything the app stores about signed-in users. Holds tokens, so it lives only in `SecureStorage`.
struct StoredAccounts: Codable, Equatable, Sendable {
    var sessions: [UserSession] = []
    var current: String?
    var lastServerURL: URL?

    var currentSession: UserSession? {
        sessions.first { $0.accountKey == current }
    }

    /// Folds in what happened this launch while the store couldn't be read, keeping what it held.
    mutating func merge(_ newer: StoredAccounts) {
        for session in newer.sessions {
            upsert(session)
        }
        current = newer.current
        lastServerURL = newer.lastServerURL ?? lastServerURL
    }

    /// Adds the session or refreshes its token, and makes it current.
    mutating func upsert(_ session: UserSession) {
        if let index = sessions.firstIndex(where: { $0.accountKey == session.accountKey }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        current = session.accountKey
        lastServerURL = session.serverURL
    }

    mutating func remove(_ session: UserSession) {
        sessions.removeAll { $0.accountKey == session.accountKey }
        if current == session.accountKey {
            current = nil
        }
    }
}

extension UserSession {
    /// Identifies one user on one server across launches.
    var accountKey: String {
        "\(serverID)/\(user.id)"
    }
}

struct SessionStore: Sendable {
    private static let account = "accounts"
    let storage: SecureStorage

    func load() throws -> StoredAccounts {
        guard let data = try storage.data(for: Self.account) else { return StoredAccounts() }
        return try JSONDecoder().decode(StoredAccounts.self, from: data)
    }

    func save(_ accounts: StoredAccounts) throws {
        try storage.set(JSONEncoder().encode(accounts), for: Self.account)
    }

    /// Forgets every user and the last server. The device ID is stored separately and stays.
    func removeAll() throws {
        try storage.remove(Self.account)
    }
}

struct DeviceIdentityStore: Sendable {
    private static let account = "device-id"
    let storage: SecureStorage

    /// The device ID is created once and kept, so the server sees one device across launches.
    func identity(deviceName: String) -> DeviceIdentity {
        DeviceIdentity(
            clientName: "Finesse",
            clientVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            deviceName: deviceName,
            deviceID: deviceID()
        )
    }

    /// A failed read isn't the same as having no ID. The stored one may still be there, so this
    /// launch uses a temporary ID and leaves the Keychain alone.
    private func deviceID() -> String {
        let stored: Data?
        do {
            stored = try storage.data(for: Self.account)
        } catch {
            return UUID().uuidString
        }
        if let stored, let id = String(data: stored, encoding: .utf8), !id.isEmpty {
            return id
        }
        let created = UUID().uuidString
        try? storage.set(Data(created.utf8), for: Self.account)
        return created
    }
}
