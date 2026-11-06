import XCTest

/// Drives the real player with the remote against the test server, on each engine, with
/// screenshots. Titles come from the environment so no library content is committed. Skips
/// without them. Playing only a few seconds leaves no saved position on the server.
@MainActor
final class PlayerFlowUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication()

    private func environment(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name] else {
            throw XCTSkip("\(name) is not set")
        }
        return value
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            usleep(500_000)
        }
    }

    private func typeInto(_ field: XCUIElement, _ text: String) {
        focus(field, in: app)
        remote.press(.select)
        sleep(1)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40) + text)
        sleep(1)
        remote.press(.menu)
        sleep(1)
    }

    private func launchSignedIn() throws {
        let server = try environment("JELLYFIN_URL")
        let username = try environment("JELLYFIN_USERNAME")
        let password = try environment("JELLYFIN_PASSWORD")
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
            typeInto(address, server)
            focus(app.buttons["connect"], in: app)
            remote.press(.select)
        }
        XCTAssertTrue(other.waitForExistence(timeout: 20))
        focus(other, in: app)
        remote.press(.select)
        let usernameField = app.textFields["username"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 10))
        typeInto(usernameField, username)
        typeInto(app.secureTextFields["password"], password)
        focus(app.buttons["signIn"], in: app)
        remote.press(.select)
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30))
    }

    /// Reaches the player the way a person does: Search, the result, then Play.
    private func openPlayer(title: String) {
        press(.up, times: 4)
        press(.left, times: 5)
        press(.right, times: 3)
        remote.press(.select)
        sleep(2)
        press(.down)
        app.typeText(title)
        sleep(4)
        press(.down, times: 5)
        sleep(2)
        remote.press(.select)
        let play = app.buttons["detailPlay"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        sleep(1)
        XCTAssertTrue(play.hasFocus)
        remote.press(.select)
    }

    private func checkPlayer(title: String, engine: String, trackMenu: String) throws {
        try launchSignedIn()
        openPlayer(title: title)

        let bar = app.buttons["transportBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 30))
        sleep(4)
        capture("\(engine)-1-controls")
        XCTAssertTrue(bar.hasFocus, "The transport bar should have focus")

        // Controls hide by themselves, and the first press brings them back.
        sleep(6)
        capture("\(engine)-2-hidden")
        remote.press(.select)
        sleep(1)
        capture("\(engine)-3-shown-again")

        // Select pauses, and play/pause on the remote resumes.
        remote.press(.select)
        sleep(1)
        capture("\(engine)-4-paused")
        remote.press(.playPause)
        sleep(2)

        // Clicks add up to a scrub, which commits by itself.
        let before = bar.value as? String
        press(.right, times: 3)
        capture("\(engine)-5-scrubbing")
        sleep(3)
        capture("\(engine)-6-after-scrub")
        XCTAssertNotEqual(bar.value as? String, before)

        // Track menu.
        let menu = app.buttons[trackMenu]
        press(.down)
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "\(trackMenu) should show")
        if !menu.hasFocus { press(.right) }
        XCTAssertTrue(menu.hasFocus, "\(trackMenu) should take focus")
        remote.press(.select)
        sleep(1)
        capture("\(engine)-7-track-menu")
        remote.press(.menu)
        sleep(1)
        press(.up)

        // Back hides the controls, then leaves, returning to the same Detail page.
        remote.press(.menu)
        sleep(1)
        capture("\(engine)-8-back-once")
        XCTAssertTrue(bar.exists, "First Back should only hide the controls")
        remote.press(.menu)
        XCTAssertTrue(app.buttons["detailPlay"].waitForExistence(timeout: 15))
        sleep(2)
        capture("\(engine)-9-back-on-detail")
    }

    func testPlayerOnAVPlayer() throws {
        try checkPlayer(title: try environment("PLAYER_AV_TITLE"), engine: "avplayer", trackMenu: "subtitleTracks")
    }

    func testPlayerOnMpv() throws {
        try checkPlayer(title: try environment("PLAYER_MPV_TITLE"), engine: "mpv", trackMenu: "subtitleTracks")
    }
}
