#if DEBUG
import Foundation
import UIKit

extension AppModel {
    /// Launch with `-FinesseFakeServer` for two signed-in users and seeded hubs with no server.
    /// The test server has one test user, so this is how switching between users gets exercised.
    static func fakeServer() -> AppModel {
        let url = URL(string: "http://fake.invalid:8096")!
        let client = InMemoryJellyfinClient(serverURL: url)
        let storage = FakeServerStorage()
        let store = SessionStore(storage: storage)
        var accounts = StoredAccounts()
        for (id, name) in [("bob", "Bob"), ("alice", "Alice")] {
            accounts.upsert(UserSession(
                serverURL: url,
                serverID: "fake-server",
                user: User(id: id, name: name),
                accessToken: "fake-\(id)"
            ))
        }
        try? store.save(accounts)
        Task {
            await client.configure {
                var resume = MediaItem(id: "resume", name: "A Film in Progress", kind: .movie)
                resume.runTime = Ticks(seconds: 6000)
                resume.userState.playbackPosition = Ticks(seconds: 1500)
                resume.productionYear = 2024
                var next = MediaItem(id: "next", name: "The Next One", kind: .episode)
                next.seriesName = "A Long Show"
                next.parentIndexNumber = 2
                next.indexNumber = 5
                $0.resumeValue = [resume]
                $0.nextUpValue = [next]
                $0.latestValue = (1...8).map { MediaItem(id: "new-\($0)", name: "New Film \($0)", kind: .movie) }
            }
        }
        return AppModel(
            store: store,
            identity: DeviceIdentity(clientName: "Finesse", clientVersion: "0", deviceName: "Fake", deviceID: "fake"),
            makeClient: { _, _ in client }
        )
    }
}

private final class FakeServerStorage: SecureStorage, @unchecked Sendable {
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
#endif
