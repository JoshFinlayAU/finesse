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

struct PrivacyManifestTests {
    @Test func theManifestShipsInTheAppAndDeclaresWhatTheBinaryUses() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        let declared = try #require(plist?["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var reasons: [String: [String]] = [:]
        for entry in declared {
            reasons[try #require(entry["NSPrivacyAccessedAPIType"] as? String)] = entry["NSPrivacyAccessedAPITypeReasons"] as? [String]
        }
        #expect(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"] == ["C617.1"])
        // mach_absolute_time left the main binary with MPVKit. Our frameworks declare it themselves.
        #expect(reasons["NSPrivacyAccessedAPICategorySystemBootTime"] == nil)
        #expect(reasons["NSPrivacyAccessedAPICategoryDiskSpace"] == nil)
    }
}
