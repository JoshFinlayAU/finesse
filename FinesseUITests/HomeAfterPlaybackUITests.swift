import XCTest

/// Runs the real player from Home against the test server, as the first test user.
/// Signs in if needed. Skips without credentials.
@MainActor
final class HomeAfterPlaybackUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication.forSignIn()
    private static let ticksPerSecond: Int64 = 10_000_000

    func testPlayPauseResumesAndHomeReloadsWhenThePlayerCloses() async throws {
        let api = try await prepare()
        let movies = try await api.movies(startIndex: 60, count: 2)
        let played = movies[0]
        let seededWhilePlaying = movies[1]
        addCleanup(api, movies)
        try await api.setResume(played)

        launchToHome()
        XCTAssertTrue(labelled(played.name).waitForExistence(timeout: 20))
        focusCard(named: played.name)
        capture("after-1-card-focused")
        remote.press(.playPause)
        waitForPlayer()
        capture("after-2-player")

        // Only a reload when the player closes can bring this one onto Home.
        try await api.setResume(seededWhilePlaying)
        closePlayer()
        capture("after-3-closed")
        XCTAssertTrue(
            labelled(seededWhilePlaying.name).waitForExistence(timeout: 15),
            "Home did not reload when the player closed"
        )

        let state = try await api.userState(played)
        expectResumed(state.positionTicks, from: played)
    }

    func testLongPressResumeStartsFromTheSavedPosition() async throws {
        let api = try await prepare()
        let movies = try await api.movies(startIndex: 62, count: 1)
        let played = movies[0]
        addCleanup(api, movies)
        try await api.setResume(played)

        launchToHome()
        XCTAssertTrue(labelled(played.name).waitForExistence(timeout: 20))
        focusCard(named: played.name)
        remote.press(.select, forDuration: 2)
        XCTAssertTrue(app.descendants(matching: .any)["Resume"].waitForExistence(timeout: 10))
        capture("menu-1-resume")
        remote.press(.select)
        waitForPlayer()
        closePlayer()

        let state = try await api.userState(played)
        expectResumed(state.positionTicks, from: played)
    }

    /// Scrubbing past the watched threshold just before leaving makes the server drop the item from
    /// Resume, so its absence shows Home reloaded with the final position rather than the seeded one.
    func testHomeReloadSeesTheStopReport() async throws {
        let api = try await prepare()
        let movies = try await api.movies(startIndex: 63, count: 1)
        let played = movies[0]
        addCleanup(api, movies)
        let nearlyWatched = played.runTimeTicks * 95 / 100 - 20 * Self.ticksPerSecond
        try await api.setResume(played, ticks: nearlyWatched)

        launchToHome()
        XCTAssertTrue(labelled(played.name).waitForExistence(timeout: 20))
        focusCard(named: played.name)
        remote.press(.playPause)
        waitForPlayer()
        remote.press(.select)
        sleep(1)
        for _ in 0..<12 {
            remote.press(.right)
            usleep(300_000)
        }
        remote.press(.select)
        sleep(2)
        capture("stop-0-scrubbed")
        closePlayer()
        capture("stop-1-closed")

        let state = try await api.userState(played)
        XCTAssertTrue(
            state.isPlayed,
            "Scrub did not pass the watched threshold: position \(state.positionTicks) of \(played.runTimeTicks)"
        )
        let gone = NSPredicate(format: "exists == false")
        let expectation = expectation(for: gone, evaluatedWith: labelled(played.name))
        await fulfillment(of: [expectation], timeout: 15)

        // The focused card has just gone, so focus must land somewhere the remote can use.
        sleep(2)
        capture("stop-2-focus-after-card-left")
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        XCTAssertTrue(focused.exists, "Nothing has focus after the played card left Home")
    }

    private func prepare() async throws -> TestServerAPI {
        let environment = ProcessInfo.processInfo.environment
        guard let server = environment["JELLYFIN_URL"],
              let username = environment["JELLYFIN_USERNAME"],
              let password = environment["JELLYFIN_PASSWORD"]
        else { throw XCTSkip("Test server variables are not set") }
        continueAfterFailure = false
        return try await TestServerAPI.signIn(server: server, username: username, password: password)
    }

    private func addCleanup(_ api: TestServerAPI, _ movies: [TestServerAPI.Movie]) {
        addTeardownBlock {
            for movie in movies {
                try await api.clearPlayedState(movie)
            }
        }
    }

    private func launchToHome() {
        let environment = ProcessInfo.processInfo.environment
        app.launch()
        let address = app.textFields["serverAddress"]
        if address.waitForExistence(timeout: 8) {
            enter(environment["JELLYFIN_URL"] ?? "", into: address, in: app)
            focus(app.buttons["connect"], in: app)
            remote.press(.select)
            let other = app.buttons["otherUser"]
            XCTAssertTrue(other.waitForExistence(timeout: 20))
            focus(other, in: app)
            remote.press(.select)
            let username = app.textFields["username"]
            XCTAssertTrue(username.waitForExistence(timeout: 10))
            enter(environment["JELLYFIN_USERNAME"] ?? "", into: username, in: app)
            enter(TypedPassword.first, into: app.secureTextFields["password"], in: app)
            focus(app.buttons["signIn"], in: app)
            remote.press(.select)
        }
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 30))
    }

    private var transportBar: XCUIElement { app.buttons["transportBar"] }

    private func waitForPlayer() {
        XCTAssertTrue(transportBar.waitForExistence(timeout: 30), "The player did not open")
        // Long enough for either engine to load and start.
        sleep(10)
    }

    /// Back steps out one level at a time, so press until the player has gone.
    private func closePlayer() {
        for _ in 0..<4 {
            remote.press(.menu)
            if transportBar.waitForNonExistence(timeout: 3) { return }
        }
        XCTFail("The player did not close")
    }

    /// Past the seeded 30 percent shows this film played and its stop report arrived. Close to it
    /// shows playback resumed there rather than starting from the beginning.
    private func expectResumed(_ ticks: Int64, from movie: TestServerAPI.Movie) {
        let seeded = movie.runTimeTicks * 3 / 10
        XCTAssertGreaterThan(ticks, seeded, "The stop report did not move the saved position")
        XCTAssertLessThan(ticks, seeded + 120 * Self.ticksPerSecond, "Playback did not resume from the saved position")
    }

    /// Other tests may leave items in Continue Watching, so find the card by name along the first row.
    private func focusCard(named name: String) {
        focusFirstHomeCard(in: app)
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<12 {
            if focused.label == name { return }
            remote.press(.right)
            sleep(1)
        }
        XCTFail("Could not focus the card for \(name)")
    }

    private func labelled(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text)).firstMatch
    }
}
