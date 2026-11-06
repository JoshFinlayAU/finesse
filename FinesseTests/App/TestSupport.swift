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
