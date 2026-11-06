import XCTest

/// Drives the real player with the remote against the test server, on each engine, with
/// screenshots. Titles come from the environment so no library content is committed. Skips
/// without them. Playing only a few seconds leaves no saved position on the server.
@MainActor
final class PlayerFlowUITests: XCTestCase {
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
        typeInto(app.secureTextFields["password"], TypedPassword.first)
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

    private func checkPlayer(title: String, engine: String) throws {
        try launchSignedIn()
        openPlayer(title: title)
        let player = PlayerDriver(app: app)
        XCTAssertTrue(player.bar.waitForExistence(timeout: 30))
        sleep(1)

        // Nothing shows during playback, and left and right do nothing at all.
        XCTAssertTrue(player.isShowing("hidden"))
        capture("\(engine)-1-nothing-showing")
        let early = player.seconds
        press(.right, times: 3)
        XCTAssertTrue(player.isShowing("hidden"), "Right should not bring anything up")
        XCTAssertLessThan(player.seconds, early + 10, "Right should not seek while playing")
        press(.left, times: 3)
        XCTAssertGreaterThanOrEqual(player.seconds, early, "Left should not seek while playing")
        XCTAssertTrue(player.isShowing("hidden"))
        XCTAssertFalse(player.isPaused)

        // Up brings the bar in, and it hides by itself.
        press(.up)
        XCTAssertTrue(player.waitFor("bar"), "Up should show the bar")
        sleep(1)
        capture("\(engine)-2-bar")
        XCTAssertTrue(player.waitFor("hidden", timeout: 8), "The bar should hide by itself")

        // Down and Back dismiss it without leaving.
        press(.up)
        XCTAssertTrue(player.waitFor("bar"))
        sleep(1)
        press(.down)
        XCTAssertTrue(player.waitFor("hidden"), "Down should dismiss the bar")
        press(.up)
        XCTAssertTrue(player.waitFor("bar"))
        press(.menu)
        XCTAssertTrue(player.waitFor("hidden"), "Back should dismiss the bar")
        XCTAssertTrue(player.bar.exists, "Back on the bar should not leave the player")

        // A click pauses and starts a scrub. Back restores the position and resumes.
        sleep(1)
        let beforeCancel = player.seconds
        remote.press(.select)
        XCTAssertTrue(player.waitFor("scrubbing"), "A click should start a scrub")
        XCTAssertTrue(player.isPaused, "A click should pause")
        press(.right, times: 6)
        XCTAssertGreaterThanOrEqual(player.seconds, beforeCancel + 55, "Right should move the scrub")
        capture("\(engine)-3-scrubbing")
        press(.menu)
        XCTAssertTrue(player.waitFor("hidden"))
        sleep(2)
        XCTAssertFalse(player.isPaused, "Back should resume what the click paused")
        XCTAssertLessThan(player.seconds, beforeCancel + 30, "Back should not keep the scrub")

        // A click commits and resumes.
        let beforeCommit = player.seconds
        remote.press(.select)
        XCTAssertTrue(player.waitFor("scrubbing"))
        press(.right, times: 4)
        remote.press(.select)
        XCTAssertTrue(player.waitFor("hidden"))
        sleep(4)
        XCTAssertFalse(player.isPaused, "A click should resume")
        XCTAssertGreaterThanOrEqual(player.seconds, beforeCommit + 40, "A click should keep the scrub")
        capture("\(engine)-4-after-commit")

        // Play/Pause toggles with nothing else showing.
        remote.press(.playPause)
        sleep(2)
        XCTAssertTrue(player.isPaused)
        XCTAssertTrue(player.isShowing("hidden"))
        capture("\(engine)-5-paused-pill")
        remote.press(.playPause)
        sleep(2)
        XCTAssertFalse(player.isPaused)

        // Real track changes through the panels, which must leave playback running.
        player.openPanel("subtitles")
        sleep(1)
        capture("\(engine)-6-subtitles")
        // The panel opens on the track in use, so go to Off first. Down from a track that's already
        // on would land on the offset's plus button, and that moves AVPlayer to mpv.
        press(.up)
        remote.press(.select)
        sleep(1)
        press(.down)
        remote.press(.select)
        sleep(4)
        capture("\(engine)-7-subtitle-on")
        press(.menu)
        // With only the bar showing, subtitles should sit above it.
        sleep(4)
        capture("\(engine)-7c-subtitle-above-bar")
        press(.menu)
        sleep(6)
        capture("\(engine)-7d-subtitle-normal")
        player.openPanel("audio")
        sleep(1)
        capture("\(engine)-8-audio")
        press(.menu)
        player.openPanel("playback")
        sleep(1)
        capture("\(engine)-9-picture-speed")
        press(.menu)
        player.openPanel("info")
        sleep(1)
        capture("\(engine)-10-info")
        let info = app.buttons["infoRows"].label
        XCTAssertTrue(info.contains(engine == "mpv" ? "mpv" : "AVPlayer"), "Should still be on \(engine): \(info)")
        press(.menu)
        XCTAssertTrue(player.waitFor("bar"), "Back should close a panel to the bar")
        press(.menu)
        XCTAssertTrue(player.waitFor("hidden"))
        let afterPanels = player.seconds
        sleep(4)
        XCTAssertGreaterThan(player.seconds, afterPanels, "Playback should still be moving")

        // With nothing showing, Back leaves. The Detail page stays under the player the whole
        // time, so only the surface disappearing shows the player has really gone.
        remote.press(.menu)
        XCTAssertTrue(player.bar.waitForNonExistence(timeout: 15), "Back should leave the player")
        XCTAssertTrue(app.buttons["detailPlay"].waitForExistence(timeout: 15))
        sleep(2)
        capture("\(engine)-11-back-on-detail")
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
        let saved = try XCTUnwrap(Int(try environment("PLAYER_RESUME_SECONDS")))
        let resumed = try XCTUnwrap(bar.value as? String)
        let position = resumed.split(separator: ",")[0].split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
        XCTAssertLessThan(abs(position - saved), 30, "Should resume at the saved \(saved)s, not \(resumed)")

        remote.press(.select)
        sleep(1)
        press(.right, times: presses)
        remote.press(.select)
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
            sleep(1)
            capture("\(label)-6-next-episode")
            let started = bar.value as? String
            XCTAssertTrue(started?.hasPrefix("0:") == true, "The next episode should play from its start: \(started ?? "")")
            sleep(12)
            capture("\(label)-6b-next-episode-picture")
            XCTAssertNotEqual(bar.value as? String, started, "The next episode should be moving")
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
