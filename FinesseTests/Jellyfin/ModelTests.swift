import Foundation
import Testing
@testable import FinEsse

@Suite struct TicksTests {
    @Test func convertsSecondsToTicks() {
        #expect(Ticks(seconds: 1.5).rawValue == 15_000_000)
        #expect(Ticks(rawValue: 600_000_000).seconds == 60)
    }

    @Test func nonFiniteSecondsBecomeZero() {
        #expect(Ticks(seconds: .nan) == .zero)
        #expect(Ticks(seconds: .infinity) == .zero)
    }

    @Test func ordersByValue() {
        #expect(Ticks(seconds: 1) < Ticks(seconds: 2))
    }
}

@Suite struct ServerAddressTests {
    @Test(arguments: [
        ("192.0.2.5", "http://192.0.2.5:8096"),
        ("192.0.2.5:9000", "http://192.0.2.5:9000"),
        ("  jellyfin.local/  ", "http://jellyfin.local:8096"),
        ("https://media.example.com/", "https://media.example.com"),
        ("HTTP://media.example.com", "http://media.example.com"),
        ("https://media.example.com/jellyfin/", "https://media.example.com/jellyfin"),
    ])
    func normalizes(input: String, expected: String) {
        #expect(ServerAddress.normalize(input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "ftp://media.example.com", "http://"])
    func rejects(input: String) {
        #expect(ServerAddress.normalize(input) == nil)
    }
}

@Suite struct PageTests {
    @Test func hasMoreUntilTotalReached() {
        #expect(Page(items: [1, 2], startIndex: 0, totalCount: 3).hasMore)
        #expect(!Page(items: [3], startIndex: 2, totalCount: 3).hasMore)
    }
}

@Suite struct InMemoryJellyfinClientTests {
    private func item(_ id: String, kind: ItemKind = .movie) -> MediaItem {
        MediaItem(id: id, name: id, kind: kind)
    }

    @Test func requiresSessionForLibraryCalls() async {
        let client = InMemoryJellyfinClient()
        await #expect(throws: JellyfinError.notSignedIn) {
            _ = try await client.libraries()
        }
    }

    @Test func rejectsWrongPassword() async {
        let client = InMemoryJellyfinClient()
        await #expect(throws: JellyfinError.invalidCredentials) {
            _ = try await client.signIn(username: "Test User", password: "nope")
        }
    }

    @Test func pagesItems() async throws {
        let client = InMemoryJellyfinClient()
        _ = try await client.signIn(username: "Test User", password: "password")
        let seeded = ["a", "b", "c"].map { item($0) }
        await client.configure { $0.allItems = seeded }
        let page = try await client.items(ItemQuery(startIndex: 1, limit: 1))
        #expect(page.items.map(\.id) == ["b"])
        #expect(page.totalCount == 3)
        #expect(page.hasMore)
    }

    @Test func quickConnectApprovesAfterPolling() async throws {
        let client = InMemoryJellyfinClient()
        let request = try await client.startQuickConnect()
        #expect(!request.isAuthenticated)
        let approved = try await client.quickConnectStatus(request)
        #expect(approved.isAuthenticated)
        let session = try await client.signIn(quickConnect: approved)
        #expect(await client.currentSession() == session)
    }

    @Test func recordsPlaybackReports() async throws {
        let client = InMemoryJellyfinClient()
        _ = try await client.signIn(username: "Test User", password: "password")
        let report = PlaybackReport(itemID: "a", position: Ticks(seconds: 5), playMethod: .directPlay)
        try await client.reportPlaybackProgress(report)
        #expect(await client.progressReports == [report])
    }
}
