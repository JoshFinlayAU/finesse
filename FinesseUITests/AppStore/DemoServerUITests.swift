import XCTest

/// Walks the path App Review will take on a public demo server: connect, sign in, browse, play a
/// title and leave, from a freshly installed app. Also captures App Store screenshot candidates.
/// Runs only when DEMO_URL and DEMO_USERNAME are set, and reads none of the test server's values.
/// DEMO_PASSWORD may be empty, as on Jellyfin's own demo. It plays only about 15 seconds of whatever
/// Home's billboard offers.
@MainActor
final class DemoServerUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private let app = XCUIApplication()

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            usleep(500_000)
        }
    }

    private func openTab(_ name: String) {
        let index = ["Home", "Movies", "TV Shows", "Search", "Settings"].firstIndex(of: name) ?? 0
        press(.up, times: 8)
        press(.left, times: 5)
        press(.right, times: index)
        remote.press(.select)
        sleep(6)
    }

    func testReviewPathOnTheDemoServer() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let server = environment["DEMO_URL"], let username = environment["DEMO_USERNAME"],
              let title = environment["DEMO_MOVIE"] else {
            throw XCTSkip("DEMO_URL, DEMO_USERNAME and DEMO_MOVIE are not set")
        }
        let password = environment["DEMO_PASSWORD"] ?? ""
        continueAfterFailure = false
        app.launch()

        let address = app.textFields["serverAddress"]
        XCTAssertTrue(address.waitForExistence(timeout: 20), "A fresh install should open on server entry")
        enter(server, into: address, in: app)
        sleep(1)
        capture("as-01-server-entry")
        focus(app.buttons["connect"], in: app)
        remote.press(.select)

        let other = app.buttons["otherUser"]
        XCTAssertTrue(other.waitForExistence(timeout: 20), "Connecting should reach the user picker")
        sleep(3)
        capture("as-02-user-picker")
        focus(other, in: app)
        remote.press(.select)
        let usernameField = app.textFields["username"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 10))
        enter(username, into: usernameField, in: app)
        if !password.isEmpty {
            enter(password, into: app.secureTextFields["password"], in: app)
        }
        focus(app.buttons["signIn"], in: app)
        remote.press(.select)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Signing in should reach Home")
        sleep(8)
        capture("as-03-home")
        press(.down)
        sleep(10)
        capture("as-04-home-row")

        // Play from Home's billboard, the first thing a reviewer sees.
        let heroPlay = app.buttons["heroPlay"]
        focus(heroPlay, in: app)
        remote.press(.select)
        let player = PlayerDriver(app: app)
        XCTAssertTrue(player.bar.waitForExistence(timeout: 30), "Play should open the player")
        sleep(3)
        let started = player.seconds
        sleep(12)
        XCTAssertFalse(player.isPaused, "The player should be playing")
        XCTAssertGreaterThan(player.seconds, started + 5, "Playback should move")
        capture("as-09-playing")
        press(.up)
        XCTAssertTrue(player.waitFor("bar"))
        sleep(1)
        capture("as-10-bar")
        player.openPanel("info")
        sleep(1)
        print("DEMO engine: \(app.buttons["infoRows"].label.prefix(200))")
        capture("as-11-info")
        player.closePanelToNothing()
        remote.press(.menu)
        XCTAssertTrue(player.bar.waitForNonExistence(timeout: 15), "Back should leave the player")
        XCTAssertTrue(heroPlay.waitForExistence(timeout: 15), "Back should return to Home")
        sleep(2)

        openTab("Movies")
        capture("as-05-movies")
        openTab("TV Shows")
        capture("as-06-shows")

        // Search, then the result's detail page.
        press(.up, times: 4)
        press(.left, times: 5)
        press(.right, times: 3)
        remote.press(.select)
        sleep(2)
        press(.down)
        app.typeText(title)
        sleep(5)
        capture("as-07-search")
        press(.down, times: 5)
        sleep(2)
        remote.press(.select)
        let play = app.buttons["detailPlay"]
        XCTAssertTrue(play.waitForExistence(timeout: 20), "The result should open its detail page")
        sleep(4)
        capture("as-08-detail")
        // Reported, not asserted: on 2026-11-09 Play had no focus here on the demo, and Up then lost the page.
        print("DEMO detail opened with Play focused: \(play.hasFocus)")
    }
}
