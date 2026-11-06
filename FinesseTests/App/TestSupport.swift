import Foundation
@testable import FinEsse

final class InMemoryStorage: SecureStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func data(for account: String) throws -> Data? {
        lock.withLock { values[account] }
    }

    func set(_ data: Data, for account: String) throws {
        lock.withLock { values[account] = data }
    }

    func remove(_ account: String) throws {
        lock.withLock { values[account] = nil }
    }
}

/// Fails reads on demand, to tell a failed read apart from an empty store.
final class FlakyStorage: SecureStorage, @unchecked Sendable {
    struct ReadFailure: Error {}

    let backing = InMemoryStorage()
    private let lock = NSLock()
    private var failing = true
    private(set) var writes = 0

    var readsFail: Bool {
        get { lock.withLock { failing } }
        set { lock.withLock { failing = newValue } }
    }

    func data(for account: String) throws -> Data? {
        if readsFail { throw ReadFailure() }
        return try backing.data(for: account)
    }

    func set(_ data: Data, for account: String) throws {
        lock.withLock { writes += 1 }
        try backing.set(data, for: account)
    }

    func remove(_ account: String) throws {
        try backing.remove(account)
    }
}

extension DeviceIdentity {
    static let test = DeviceIdentity(clientName: "Finesse", clientVersion: "0", deviceName: "Test", deviceID: "device-1")
}

extension UserSession {
    static func test(
        user: String = "user-1",
        name: String = "Test User",
        server: URL = URL(string: "http://fake.invalid:8096")!,
        token: String = "fake-token"
    ) -> UserSession {
        UserSession(serverURL: server, serverID: "fake-server", user: User(id: user, name: name), accessToken: token)
    }
}

extension MediaItem {
    static func test(_ id: String, kind: ItemKind = .movie, position: Ticks = .zero) -> MediaItem {
        var item = MediaItem(id: id, name: "Item \(id)", kind: kind)
        item.userState.playbackPosition = position
        return item
    }
}

@MainActor
func makeApp(
    client: any JellyfinClient = InMemoryJellyfinClient(),
    storage: InMemoryStorage = InMemoryStorage()
) -> AppModel {
    AppModel(store: SessionStore(storage: storage), identity: .test, makeClient: { _, _ in client })
}
