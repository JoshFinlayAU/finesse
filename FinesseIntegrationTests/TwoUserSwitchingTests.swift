import Foundation
import Testing
@testable import FinEsse

private struct TwoUsers {
    let url: URL
    let first: (name: String, password: String)
    let second: (name: String, password: String)

    static var current: TwoUsers? {
        let environment = ProcessInfo.processInfo.environment
        guard
            let urlString = environment["JELLYFIN_URL"],
            let url = URL(string: urlString),
            let firstName = environment["JELLYFIN_USERNAME"],
            let firstPassword = environment["JELLYFIN_PASSWORD"],
            let secondName = environment["JELLYFIN_USERNAME_2"],
            let secondPassword = environment["JELLYFIN_PASSWORD_2"]
        else { return nil }
        return TwoUsers(url: url, first: (firstName, firstPassword), second: (secondName, secondPassword))
    }
}

@Suite(.enabled(if: TwoUsers.current != nil, "The second test user's variables are not set"))
struct TwoUserSwitchingTests {
    /// One install has one DeviceId, so both users' tokens and resume state must survive side by side.
    @Test func usersOnOneDeviceKeepSeparateTokensAndResumeState() async throws {
        let users = try #require(TwoUsers.current)
        let device = DeviceIdentity(
            clientName: "Finesse Tests",
            clientVersion: "0",
            deviceName: "Switching Tests",
            deviceID: "finesse-integration-switching"
        )
        let client = LiveJellyfinClient(serverURL: users.url, device: device)
        let first = try await client.signIn(username: users.first.name, password: users.first.password)
        let second = try await client.signIn(username: users.second.name, password: users.second.password)

        let movies = try await client.items(ItemQuery(kinds: [.movie], startIndex: 20, limit: 2)).items
        try #require(movies.count == 2)
        let firstMovie = movies[0]
        let secondMovie = movies[1]

        await client.setSession(first)
        try await report(firstMovie, on: client)
        await client.setSession(second)
        try await report(secondMovie, on: client)

        await client.setSession(first)
        let firstResume = try await client.resumeItems(limit: 50).map(\.id)
        await client.setSession(second)
        let secondResume = try await client.resumeItems(limit: 50).map(\.id)

        // Clear before asserting, so a failure doesn't leave state behind.
        _ = try await client.setPlayed(false, itemID: secondMovie.id)
        await client.setSession(first)
        _ = try await client.setPlayed(false, itemID: firstMovie.id)

        #expect(firstResume.contains(firstMovie.id))
        #expect(!firstResume.contains(secondMovie.id))
        #expect(secondResume.contains(secondMovie.id))
        #expect(!secondResume.contains(firstMovie.id))

        // Signing one user out leaves the other working, with no new sign-in.
        await client.setSession(second)
        try await client.signOut()
        await client.setSession(first)
        _ = try await client.resumeItems(limit: 1)
        await client.setSession(second)
        await #expect(throws: JellyfinError.notSignedIn) {
            _ = try await client.resumeItems(limit: 1)
        }
        await client.setSession(first)
        try await client.signOut()
    }

    /// 30 percent falls inside the server's resume thresholds.
    private func report(_ movie: MediaItem, on client: LiveJellyfinClient) async throws {
        let runTime = try #require(movie.runTime)
        try await client.reportPlaybackProgress(PlaybackReport(
            itemID: movie.id,
            position: Ticks(rawValue: runTime.rawValue * 3 / 10),
            playMethod: .directPlay
        ))
    }
}
