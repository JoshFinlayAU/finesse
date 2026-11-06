import Foundation
import Testing
@testable import FinEsse

struct SecureStorageTests {
    @Test func keychainRoundTrips() throws {
        let storage = KeychainStorage(service: "Finesse.Tests.\(UUID().uuidString)")
        defer { try? storage.remove("item") }

        #expect(try storage.data(for: "item") == nil)
        try storage.set(Data("one".utf8), for: "item")
        try storage.set(Data("two".utf8), for: "item")
        #expect(try storage.data(for: "item") == Data("two".utf8))
        try storage.remove("item")
        #expect(try storage.data(for: "item") == nil)
    }

    @Test func deviceIDStaysTheSameAcrossLaunches() {
        let storage = InMemoryStorage()
        let first = DeviceIdentityStore(storage: storage).identity(deviceName: "One")
        let second = DeviceIdentityStore(storage: storage).identity(deviceName: "One")
        #expect(first.deviceID == second.deviceID)
        #expect(!first.deviceID.isEmpty)
    }

    @Test func signingInAgainRefreshesTheTokenWithoutDuplicating() {
        var accounts = StoredAccounts()
        accounts.upsert(.test(token: "old"))
        accounts.upsert(.test(token: "new"))
        #expect(accounts.sessions.count == 1)
        #expect(accounts.currentSession?.accessToken == "new")
    }
}
