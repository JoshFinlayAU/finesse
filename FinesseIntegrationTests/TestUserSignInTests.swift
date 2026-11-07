import Foundation
import Testing

private struct TestServer {
    let url: URL
    let username: String
    let password: String

    static var current: TestServer? {
        let environment = ProcessInfo.processInfo.environment
        guard
            let urlString = environment["JELLYFIN_URL"],
            let url = URL(string: urlString),
            let username = environment["JELLYFIN_USERNAME"],
            let password = environment["JELLYFIN_PASSWORD"]
        else { return nil }
        return TestServer(url: url, username: username, password: password)
    }
}

private struct AuthenticationResult: Decodable {
    struct User: Decodable {
        struct Policy: Decodable {
            let IsAdministrator: Bool
        }

        let Name: String
        let Policy: Policy
    }

    let User: User
    let AccessToken: String
}

@Suite(.enabled(if: TestServer.current != nil, "JELLYFIN_URL, JELLYFIN_USERNAME or JELLYFIN_PASSWORD is not set"))
struct TestUserSignInTests {
    @Test func testUserSignsInWithoutAdminRights() async throws {
        let server = try #require(TestServer.current)

        var request = URLRequest(url: server.url.appending(path: "Users/AuthenticateByName"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            #"MediaBrowser Client="Finesse Tests", Device="Simulator", DeviceId="finesse-integration-tests", Version="0""#,
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try JSONEncoder().encode(["Username": server.username, "Pw": server.password])

        // Not URLSession.shared: its cache belongs to the app these tests run inside.
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let result = try JSONDecoder().decode(AuthenticationResult.self, from: data)
        #expect(result.User.Name == server.username)
        #expect(!result.User.Policy.IsAdministrator)
        #expect(!result.AccessToken.isEmpty)
    }
}
