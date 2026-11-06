import Foundation
import Testing
@testable import FinEsse

@MainActor
struct KeychainFailureTests {
    private func model(_ storage: SecureStorage, client: any JellyfinClient) -> AppModel {
        AppModel(store: SessionStore(storage: storage), identity: .test, makeClient: { _, _ in client })
    }

    private func storageHoldingAlice() async throws -> FlakyStorage {
        let storage = FlakyStorage()
        try SessionStore(storage: storage.backing).save({
            var accounts = StoredAccounts()
            accounts.upsert(.test(user: "alice", name: "Alice"))
            return accounts
        }())
        return storage
    }

    @Test func failedReadKeepsTheStoredDeviceID() throws {
        let storage = FlakyStorage()
        try storage.backing.set(Data("original".utf8), for: "device-id")

        let during = DeviceIdentityStore(storage: storage).identity(deviceName: "One").deviceID
        #expect(during != "original")
        #expect(storage.writes == 0)

        storage.readsFail = false
        #expect(DeviceIdentityStore(storage: storage).identity(deviceName: "One").deviceID == "original")
    }

    @Test func notFoundCreatesAndKeepsADeviceID() {
        let storage = FlakyStorage()
        storage.readsFail = false
        let first = DeviceIdentityStore(storage: storage).identity(deviceName: "One").deviceID
        #expect(storage.writes == 1)
        #expect(DeviceIdentityStore(storage: storage).identity(deviceName: "One").deviceID == first)
    }

    @Test func signingInWhileTheStoreCantBeReadDoesNotOverwriteIt() async throws {
        let storage = try await storageHoldingAlice()
        let client = InMemoryJellyfinClient()
        let app = model(storage, client: client)
        await app.restore()
        #expect(app.phase == .signedOut)

        await app.completeSignIn(.test(user: "bob", name: "Bob"), client: client)

        #expect(app.session?.user.name == "Bob")
        #expect(storage.writes == 0)
        let stored = try SessionStore(storage: storage.backing).load()
        #expect(stored.sessions.map(\.user.name) == ["Alice"])
    }

    @Test func aSaveAfterTheStoreRecoversKeepsBothUsers() async throws {
        let storage = try await storageHoldingAlice()
        let client = InMemoryJellyfinClient()
        let app = model(storage, client: client)
        await app.restore()
        await app.completeSignIn(.test(user: "bob", name: "Bob"), client: client)

        storage.readsFail = false
        await app.switchUser(to: .test(user: "bob", name: "Bob"))

        let stored = try SessionStore(storage: storage.backing).load()
        #expect(stored.sessions.map(\.user.name) == ["Alice", "Bob"])
        #expect(stored.currentSession?.user.name == "Bob")
        #expect(app.knownSessions(on: UserSession.test().serverURL).count == 2)
    }

    @Test func undecodableDataIsReplacedBecauseNothingCanReadIt() async throws {
        let storage = FlakyStorage()
        storage.readsFail = false
        try storage.backing.set(Data("not json".utf8), for: "accounts")
        let client = InMemoryJellyfinClient()
        let app = model(storage, client: client)
        await app.restore()
        #expect(app.phase == .signedOut)

        await app.completeSignIn(.test(), client: client)

        #expect(try SessionStore(storage: storage.backing).load().sessions.count == 1)
    }
}
