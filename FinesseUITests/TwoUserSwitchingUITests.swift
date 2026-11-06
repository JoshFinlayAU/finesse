import XCTest

/// Drives the real app against the test server with both test users. Reset the simulator keychain
/// first, so it starts signed out. Skips when the second user's variables are absent.
/// Keeps no screenshot of the user picker, which shows household names on this server.
@MainActor
final class TwoUserSwitchingUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication()

    private func environment(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name] else {
            throw XCTSkip("\(name) is not set")
        }
        return value
    }

    func testSwitchBackAndForthKeepsEachUsersHomeAndSignOutLeavesTheOther() async throws {
        let server = try environment("JELLYFIN_URL")
        let firstName = try environment("JELLYFIN_USERNAME")
        let firstPassword = try environment("JELLYFIN_PASSWORD")
        let secondName = try environment("JELLYFIN_USERNAME_2")
        let secondPassword = try environment("JELLYFIN_PASSWORD_2")
        continueAfterFailure = false

        // Give each user a different movie to resume, through the API on its own DeviceId,
        // so seeding never touches the tokens the app holds.
        let firstAPI = try await TestServerAPI.signIn(server: server, username: firstName, password: firstPassword)
        let secondAPI = try await TestServerAPI.signIn(server: server, username: secondName, password: secondPassword)
        let movies = try await firstAPI.movies(startIndex: 40, count: 2)
        let firstMovie = movies[0]
        let secondMovie = movies[1]
        try await firstAPI.setResume(firstMovie)
        try await secondAPI.setResume(secondMovie)
        addTeardownBlock {
            try await firstAPI.clearResume(firstMovie)
            try await secondAPI.clearResume(secondMovie)
        }

        // First user signs in, and sees only their own movie in Continue Watching.
        app.launch()
        let address = app.textFields["serverAddress"]
        XCTAssertTrue(address.waitForExistence(timeout: 20))
        enter(server, into: address, in: app)
        focus(app.buttons["connect"], in: app)
        remote.press(.select)
        signInAsOtherUser(firstName, password: firstPassword)
        expectHome(showing: firstMovie.name, notShowing: secondMovie.name)
        capture("switch-1-first-user-home")

        // Second user is added from Settings, and sees only theirs.
        openSettings()
        focus(app.buttons["addUser"], in: app)
        remote.press(.select)
        signInAsOtherUser(secondName, password: secondPassword)
        expectHome(showing: secondMovie.name, notShowing: firstMovie.name)
        capture("switch-2-second-user-home")

        // Back and forth with no password.
        for _ in 0..<2 {
            switchTo(firstName)
            expectHome(showing: firstMovie.name, notShowing: secondMovie.name)
            switchTo(secondName)
            expectHome(showing: secondMovie.name, notShowing: firstMovie.name)
        }
        openSettings()
        capture("switch-3-settings-both-users")

        // The second user is restored after a relaunch.
        app.terminate()
        app.launch()
        expectHome(showing: secondMovie.name, notShowing: firstMovie.name)

        // Sign the first user out while they are current. The second is offered with no password,
        // and Home loading for them shows their token still works.
        switchTo(firstName)
        expectHome(showing: firstMovie.name, notShowing: secondMovie.name)
        openSettings()
        focus(app.buttons["signOut"], in: app)
        remote.press(.select)
        let held = app.buttons["user-\(secondName)"]
        XCTAssertTrue(held.waitForExistence(timeout: 20))
        focus(held, in: app)
        remote.press(.select)
        expectHome(showing: secondMovie.name, notShowing: firstMovie.name)
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
        capture("switch-4-second-user-after-first-signed-out")

        openSettings()
        XCTAssertFalse(app.buttons["account-\(firstName)"].exists)
        focus(app.buttons["signOut"], in: app)
        remote.press(.select)
        XCTAssertTrue(app.buttons["otherUser"].waitForExistence(timeout: 20))
    }

    private func signInAsOtherUser(_ username: String, password: String) {
        let other = app.buttons["otherUser"]
        XCTAssertTrue(other.waitForExistence(timeout: 20))
        focus(other, in: app)
        remote.press(.select)
        let usernameField = app.textFields["username"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 10))
        enter(username, into: usernameField, in: app)
        enter(password, into: app.secureTextFields["password"], in: app)
        focus(app.buttons["signIn"], in: app)
        remote.press(.select)
    }

    private func switchTo(_ username: String) {
        openSettings()
        focus(app.buttons["account-\(username)"], in: app)
        remote.press(.select)
    }

    private func openSettings() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        focus(app.tabBars.buttons["Home"], in: app)
        for _ in 0..<4 {
            remote.press(.right)
            usleep(500_000)
        }
        remote.press(.select)
        XCTAssertTrue(app.buttons["signOut"].waitForExistence(timeout: 10))
        sleep(1)
    }

    private func expectHome(showing expected: String, notShowing other: String) {
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 30))
        XCTAssertTrue(labelled(expected).waitForExistence(timeout: 20), "Home should show \(expected)")
        XCTAssertFalse(labelled(other).exists, "Home should not show \(other)")
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
    }

    private func labelled(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text)).firstMatch
    }
}

/// Seeds one user's own resume position on the test server.
struct TestServerAPI: Sendable {
    struct Movie: Sendable {
        let id: String
        let name: String
        let runTimeTicks: Int64
    }

    let server: String
    let userID: String
    let token: String

    static func signIn(server: String, username: String, password: String) async throws -> TestServerAPI {
        let body = try JSONSerialization.data(withJSONObject: ["Username": username, "Pw": password])
        let data = try await send("POST", "\(server)/Users/AuthenticateByName", token: nil, body: body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let user = json?["User"] as? [String: Any]
        guard let token = json?["AccessToken"] as? String, let userID = user?["Id"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return TestServerAPI(server: server, userID: userID, token: token)
    }

    func movies(startIndex: Int, count: Int) async throws -> [Movie] {
        let query = "includeItemTypes=Movie&recursive=true&sortBy=SortName&startIndex=\(startIndex)&limit=\(count)"
        let data = try await Self.send("GET", "\(server)/Items?\(query)", token: token, body: nil)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = json?["Items"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let id = item["Id"] as? String, let name = item["Name"] as? String,
                  let ticks = (item["RunTimeTicks"] as? NSNumber)?.int64Value
            else { return nil }
            return Movie(id: id, name: name, runTimeTicks: ticks)
        }
    }

    func setResume(_ movie: Movie) async throws {
        try await setPosition(movie, ticks: movie.runTimeTicks * 3 / 10)
    }

    func clearResume(_ movie: Movie) async throws {
        try await setPosition(movie, ticks: 0)
    }

    /// Puts a movie at a given fraction of its length, for tests that need a position other than 30 percent.
    func setResume(_ movie: Movie, ticks: Int64) async throws {
        try await setPosition(movie, ticks: ticks)
    }

    /// The saved position and watched flag, as the server has them now.
    func userState(_ movie: Movie) async throws -> (positionTicks: Int64, isPlayed: Bool) {
        let data = try await Self.send("GET", "\(server)/Items/\(movie.id)?userId=\(userID)", token: token, body: nil)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let state = json?["UserData"] as? [String: Any]
        return ((state?["PlaybackPositionTicks"] as? NSNumber)?.int64Value ?? 0, state?["Played"] as? Bool ?? false)
    }

    /// Clears position and play count together.
    func clearPlayedState(_ movie: Movie) async throws {
        _ = try await Self.send("DELETE", "\(server)/UserPlayedItems/\(movie.id)?userId=\(userID)", token: token, body: nil)
    }

    private func setPosition(_ movie: Movie, ticks: Int64) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["PlaybackPositionTicks": ticks])
        _ = try await Self.send("POST", "\(server)/UserItems/\(movie.id)/UserData?userId=\(userID)", token: token, body: body)
    }

    private static func send(_ method: String, _ url: String, token: String?, body: Data?) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var header = #"MediaBrowser Client="Finesse UI Tests", Device="Simulator", DeviceId="finesse-ui-tests-seed", Version="0""#
        if let token { header += #", Token="\#(token)""# }
        request.setValue(header, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
