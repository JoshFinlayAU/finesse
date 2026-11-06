import Foundation

/// What the Top Shelf extension needs to ask the server for the active user's rows. Holds a token,
/// so it only goes in a keychain group shared with the extension. That group holds this one session,
/// so the extension can't reach the tokens of the other users in the app's own store.
struct TopShelfSharedSession: Codable, Equatable, Sendable {
    var session: UserSession
    var device: DeviceIdentity
}

struct TopShelfSessionStore: Sendable {
    /// In both targets' `keychain-access-groups`.
    static let accessGroup = "4S7BG5A4XV.au.com.athenanetworks.finesse.shared"
    private static let account = "top-shelf-session"

    let storage: SecureStorage

    static var live: TopShelfSessionStore {
        TopShelfSessionStore(storage: KeychainStorage(service: "Finesse.TopShelf", accessGroup: accessGroup))
    }

    func load() throws -> TopShelfSharedSession? {
        try storage.data(for: Self.account).map { try JSONDecoder().decode(TopShelfSharedSession.self, from: $0) }
    }

    func save(_ shared: TopShelfSharedSession) throws {
        try storage.set(JSONEncoder().encode(shared), for: Self.account)
    }

    func clear() throws {
        try storage.remove(Self.account)
    }
}
