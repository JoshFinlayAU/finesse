import XCTest

/// The real shelf on the simulator's Home Screen, drawn by the system from our extension, against
/// the test server. Skips without credentials. Changes only the test user's own state and undoes it.
@MainActor
final class TopShelfUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication.forSignIn()

    private func environment(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name] else {
            throw XCTSkip("\(name) is not set")
        }
        return value
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            usleep(600_000)
        }
    }

    private func launchSignedIn() throws {
        let server = try environment("JELLYFIN_URL")
        let username = try environment("JELLYFIN_USERNAME")
        _ = try environment("JELLYFIN_PASSWORD")
        continueAfterFailure = false
        app.launch()

        let tabBar = app.tabBars.firstMatch
        let address = app.textFields["serverAddress"]
        let other = app.buttons["otherUser"]
        let deadline = Date.now.addingTimeInterval(30)
        while !tabBar.exists, !address.exists, !other.exists, Date.now < deadline {
            usleep(500_000)
        }
        if tabBar.exists { return }
        if address.exists {
            enter(server, into: address, in: app)
            focus(app.buttons["connect"], in: app)
            remote.press(.select)
        }
        XCTAssertTrue(other.waitForExistence(timeout: 20))
        focus(other, in: app)
        remote.press(.select)
        let usernameField = app.textFields["username"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 10))
        enter(username, into: usernameField, in: app)
        enter(TypedPassword.first, into: app.secureTextFields["password"], in: app)
        focus(app.buttons["signIn"], in: app)
        remote.press(.select)
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30))
    }

    /// The Home Screen reports no focus labels to XCUITest. Its top row on our simulator is Settings,
    /// then Finesse, so this goes by position and the screenshots show that it landed there.
    private func focusFinesseIcon() {
        press(.left, times: 4)
        press(.right)
    }

    private func showShelf(_ name: String) {
        remote.press(.home)
        sleep(4)
        focusFinesseIcon()
        // Long enough for the system to run the extension and fetch the images.
        sleep(12)
        capture(name)
    }

    /// Asked for by name, because it drives the simulator's Home Screen rather than the app. The
    /// Home Screen reports nothing about the shelf, so what it shows is proved by the screenshots,
    /// and what the items do is proved by where the app ends up.
    func testTheShelfFollowsTheUserAndItsItemsOpenTheApp() async throws {
        _ = try environment("FINESSE_TOP_SHELF_TEST")
        let api = try await TestServerAPI.signIn(
            server: try environment("JELLYFIN_URL"),
            username: try environment("JELLYFIN_USERNAME"),
            password: try environment("JELLYFIN_PASSWORD")
        )
        let movies = try await api.movies(startIndex: 60, count: 1)
        let movie = try XCTUnwrap(movies.first)
        try await api.setResume(movie)
        addTeardownBlock { try await api.clearPlayedState(movie) }

        try launchSignedIn()
        sleep(3)

        // A cold start: the app isn't running when the item is chosen.
        app.terminate()
        showShelf("shelf-1-continue-watching")
        press(.up)
        sleep(2)
        capture("shelf-2-in-the-shelf")
        remote.press(.select)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "Choosing an item should open Finesse")
        XCTAssertTrue(app.buttons["detailWatched"].waitForExistence(timeout: 30), "Select on a shelf item should open its Detail")
        sleep(3)
        capture("shelf-3-cold-start-detail")

        // Watch state changing should change the shelf: that title leaves Continue Watching.
        focus(app.buttons["detailWatched"], in: app)
        remote.press(.select)
        sleep(3)
        showShelf("shelf-4-after-marking-watched")

        // Already running: Play goes straight to the player.
        press(.up)
        sleep(2)
        remote.press(.playPause)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(
            app.descendants(matching: .any)["transportBar"].waitForExistence(timeout: 30),
            "Play on a shelf item should open the player"
        )
        sleep(6)
        capture("shelf-5-play-while-running")
        press(.menu)
        sleep(2)
        press(.menu)
        sleep(3)

        // Signing out should leave only the static image.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        press(.menu)
        focus(app.tabBars.buttons["Home"], in: app)
        press(.right, times: 4)
        remote.press(.select)
        XCTAssertTrue(app.buttons["signOut"].waitForExistence(timeout: 10))
        sleep(1)
        focus(app.buttons["signOut"], in: app)
        remote.press(.select)
        XCTAssertTrue(app.buttons["otherUser"].waitForExistence(timeout: 20), "Sign-out should reach the user picker")
        showShelf("shelf-6-signed-out")
    }
}
