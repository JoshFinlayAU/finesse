import Foundation
import Testing
@testable import FinEsse

/// The live connection against the test server, as the test user. Marks one unwatched film
/// watched and checks the server says so on the connection, then marks it unwatched again.
@Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["JELLYFIN_URL"] != nil, "JELLYFIN_* variables not set"),
    .disabled(if: TestPlanScope.playbackOnly, "Playback.xctestplan runs only the streaming suites")
)
struct LiveUpdatesTests {
    private func signedInClient() async throws -> LiveJellyfinClient {
        let environment = ProcessInfo.processInfo.environment
        let client = LiveJellyfinClient(
            serverURL: try #require(environment["JELLYFIN_URL"].flatMap(URL.init(string:))),
            device: DeviceIdentity(
                clientName: "Finesse Integration Tests",
                clientVersion: "1.0",
                deviceName: "Simulator",
                // Its own, because signing in again on one DeviceId revokes the other suites' token.
                deviceID: "finesse-integration-tests-live"
            )
        )
        _ = try await client.signIn(
            username: try #require(environment["JELLYFIN_USERNAME"]),
            password: try #require(environment["JELLYFIN_PASSWORD"])
        )
        return client
    }

    @Test func markingWatchedArrivesOnTheConnection() async throws {
        let client = try await signedInClient()
        var unwatched = ItemFilter()
        unwatched.isPlayed = false
        // One with no progress either, since marking it unwatched again would clear that.
        let film = try #require(
            try await client.items(ItemQuery(kinds: [.movie], filter: unwatched, limit: 20)).items
                .first { $0.userState.playbackPosition == .zero },
            "The test user should have an unwatched film with no progress"
        )

        let live = LiveUpdates(source: client)
        // Listening from before the change, so nothing is missed.
        let events = live.events.stream()
        await live.start()
        for _ in 0..<100 {
            if await live.isConnected { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(await live.isConnected, "The server should answer on /socket within 10 seconds")

        _ = try await client.setPlayed(true, itemID: film.id)
        var sawIt = false
        do {
            sawIt = try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    try await Task.sleep(for: .seconds(20))
                    return false
                }
                group.addTask {
                    for await event in events {
                        if case .userDataChanged(let changes) = event,
                           changes.contains(where: { $0.itemID == film.id && $0.isPlayed }) {
                            return true
                        }
                    }
                    return false
                }
                let first = try await group.next() ?? false
                group.cancelAll()
                return first
            }
        } catch {}
        // Undo before checking, so a failure still leaves the test user as it was.
        let restored = try await client.setPlayed(false, itemID: film.id)
        await live.stop()
        #expect(!restored.isPlayed)
        #expect(sawIt, "UserDataChanged for the film should arrive within 20 seconds")
    }
}
