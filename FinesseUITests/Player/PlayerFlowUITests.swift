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

    private func isPaused(_ bar: XCUIElement) -> Bool {
        (bar.value as? String)?.contains("paused") == true
    }

    /// Moves down from the bar to a track button. Left and right scrub while the bar has focus, so
    /// they're only pressed once focus is known to have left it. Audio is the leftmost button.
    private func focusTrackButton(_ menu: XCUIElement) {
        let bar = app.buttons["transportBar"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "\(menu) should show")
        let onButtons = { (bar.value as? String)?.contains("track buttons focused") == true }
        for _ in 0..<5 where !onButtons() {
            press(.down)
            sleep(1)
        }
        XCTAssertTrue(onButtons(), "Down should reach the track buttons")
        press(.left)
        if menu.identifier == "subtitleTracks" {
            press(.right)
        }
    }

    /// Opens a track menu, moves to another row and picks it, as a person would.
    private func pickTrack(in menuID: String, moving: XCUIRemote.Button, engine: String) {
        let menu = app.buttons[menuID]
        focusTrackButton(menu)
        let position = app.buttons["transportBar"].value as? String
        remote.press(.select)
        sleep(1)
        capture("\(engine)-\(menuID)-open")
        press(moving)
        remote.press(.select)
        sleep(4)
        capture("\(engine)-\(menuID)-picked")
        XCTAssertNotEqual(app.buttons["transportBar"].value as? String, position)
    }

    private func checkPlayer(title: String, engine: String) throws {
        try launchSignedIn()
        openPlayer(title: title)

        let bar = app.buttons["transportBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 30))
        sleep(1)
        capture("\(engine)-1-controls")

        // Controls hide by themselves, leaving just the picture, and time keeps moving.
        let early = bar.value as? String
        sleep(9)
        capture("\(engine)-2-hidden")
        XCTAssertNotEqual(bar.value as? String, early, "Playback should be moving")
        sleep(10)
        capture("\(engine)-2b-picture-later")

        // The first select only brings the controls back.
        remote.press(.select)
        sleep(1)
        capture("\(engine)-3-shown-again")
        XCTAssertFalse(isPaused(bar), "Select on hidden controls should not pause")

        // The next select pauses, and play/pause on the remote resumes.
        remote.press(.select)
        sleep(1)
        capture("\(engine)-4-paused")
        XCTAssertTrue(isPaused(bar), "Select on visible controls should pause")
        remote.press(.playPause)
        sleep(2)
        XCTAssertFalse(isPaused(bar), "Play/pause should resume")

        // Clicks add up to a scrub, which commits by itself.
        let before = bar.value as? String
        press(.right, times: 3)
        capture("\(engine)-5-scrubbing")
        sleep(3)
        capture("\(engine)-6-after-scrub")
        XCTAssertNotEqual(bar.value as? String, before)

        // Real track changes through the menus, which must leave playback running.
        pickTrack(in: "subtitleTracks", moving: .up, engine: engine)
        pickTrack(in: "audioTracks", moving: .down, engine: engine)
        XCTAssertTrue(bar.waitForExistence(timeout: 30), "The player should still be up")
        let afterTracks = bar.value as? String
        sleep(4)
        XCTAssertNotEqual(bar.value as? String, afterTracks, "Playback should still be moving")
        capture("\(engine)-7-after-tracks")

        // Back hides the controls, then leaves. The Detail page exists under the player the
        // whole time, so only the bar disappearing shows the player has really gone.
        press(.up)
        sleep(1)
        capture("\(engine)-8-before-back")
        remote.press(.menu)
        sleep(1)
        capture("\(engine)-8b-back-once")
        XCTAssertTrue(bar.exists, "First Back should only hide the controls")
        remote.press(.menu)
        XCTAssertTrue(bar.waitForNonExistence(timeout: 15), "Second Back should leave the player")
        XCTAssertTrue(app.buttons["detailPlay"].waitForExistence(timeout: 15))
        sleep(2)
        capture("\(engine)-9-back-on-detail")
    }

    /// Needs an episode seeded at about 88 percent, so it leads Continue Watching. The server resets
    /// positions much later than that, so the test scrubs the rest of the way with the remote.
    func testResumeFromHomeThenUpNext() throws {
        let presses = Int(try environment("PLAYER_SCRUB_PRESSES")) ?? 0
        let action = try environment("PLAYER_UP_NEXT_ACTION")
        let label = "upnext-\(action)"
        try launchSignedIn()
        sleep(3)
        capture("\(label)-1-home")

        let play = app.buttons["detailPlay"]
        for _ in 0..<4 where !play.exists {
            remote.press(.select)
            sleep(2)
            if !play.exists && !app.buttons["transportBar"].exists {
                press(.down)
            }
        }
        if play.exists {
            sleep(1)
            capture("\(label)-2-detail-resume")
            remote.press(.select)
        }

        let bar = app.buttons["transportBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 30))
        sleep(2)
        capture("\(label)-3-resumed")
        let resumed = bar.value as? String
        XCTAssertFalse(resumed?.hasPrefix("0:0") == true, "Should resume from the saved position, not the start: \(resumed ?? "")")

        press(.right, times: presses)
        sleep(2)
        capture("\(label)-4-near-end")

        let upNextPlay = app.buttons["upNextPlay"]
        XCTAssertTrue(upNextPlay.waitForExistence(timeout: 90), "Up next should appear at the end of the episode")
        sleep(2)
        capture("\(label)-5-up-next")

        if action == "cancel" {
            press(.right)
            remote.press(.select)
            XCTAssertTrue(bar.waitForNonExistence(timeout: 15), "Cancel should leave the player")
            sleep(2)
            capture("\(label)-6-after-cancel")
            XCTAssertFalse(upNextPlay.exists)
        } else {
            // Leave the remote alone: the countdown should start the next episode by itself.
            XCTAssertTrue(upNextPlay.waitForNonExistence(timeout: 20), "The countdown should finish")
            XCTAssertTrue(bar.waitForExistence(timeout: 30), "The next episode should start")
            press(.up)
            sleep(1)
            capture("\(label)-6-next-episode")
            let started = bar.value as? String
            XCTAssertTrue(started?.hasPrefix("0:") == true, "The next episode should play from its start: \(started ?? "")")
            sleep(12)
            capture("\(label)-6b-next-episode-picture")
            XCTAssertNotEqual(bar.value as? String, started, "The next episode should be moving")
            press(.up)
            remote.press(.menu)
            sleep(1)
            remote.press(.menu)
            XCTAssertTrue(bar.waitForNonExistence(timeout: 15), "Back should leave the player")
            sleep(2)
            capture("\(label)-7-after-back")
        }
    }

    func testPlayerOnAVPlayer() throws {
        try checkPlayer(title: try environment("PLAYER_AV_TITLE"), engine: "avplayer")
    }

    func testPlayerOnMpv() throws {
        try checkPlayer(title: try environment("PLAYER_MPV_TITLE"), engine: "mpv")
    }
}
