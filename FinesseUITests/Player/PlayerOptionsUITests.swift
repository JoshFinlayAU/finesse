import XCTest

/// Every panel, driven with the remote on seeded playback: no server, video or real engine, but the
/// real screen, model and session. PlayerFlowUITests covers real media on each engine.
@MainActor
final class PlayerOptionsUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication()
    private lazy var player = PlayerDriver(app: app)

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            usleep(500_000)
        }
    }

    private func engineLabel() -> String {
        app.descendants(matching: .any)["seededEngine"].label
    }

    /// Home's first row is Continue Watching, which is a film. Next Up, below it, is an episode.
    private func openPlayer(onNextUp: Bool = false, _ arguments: String...) {
        continueAfterFailure = false
        app.launchArguments = ["-FinesseFakeServer", "-FinesseSeededPlayback", "-FinesseSeededNoSegments"] + arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        sleep(1)
        focusFirstHomeCard(in: app)
        if onNextUp {
            press(.down)
            sleep(1)
        }
        remote.press(.select)
        let play = app.buttons["detailPlay"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        sleep(1)
        remote.press(.select)
        XCTAssertTrue(player.bar.waitForExistence(timeout: 15))
        player.expectSilent()
        sleep(1)
    }

    private func value(_ id: String) -> String {
        app.descendants(matching: .any)["\(id)-value"].label
    }

    func testRemoteRules() throws {
        openPlayer()
        XCTAssertTrue(player.isShowing("hidden"))
        XCTAssertFalse(app.descendants(matching: .any)["scrubBar"].exists)

        let early = player.seconds
        press(.right, times: 2)
        press(.left, times: 2)
        XCTAssertTrue(player.isShowing("hidden"), "Left and right should bring nothing up")
        XCTAssertLessThan(abs(player.seconds - early), 8, "Left and right should not seek")

        remote.press(.select)
        XCTAssertTrue(player.waitFor("scrubbing"))
        XCTAssertTrue(player.isPaused)
        XCTAssertTrue(app.descendants(matching: .any)["scrubBar"].waitForExistence(timeout: 2))
        sleep(1)
        capture("options-scrub-bar")
        let origin = player.seconds
        press(.right, times: 3)
        XCTAssertEqual(player.seconds, origin + 30)
        press(.left)
        XCTAssertEqual(player.seconds, origin + 20)

        // Play/Pause commits like a click.
        remote.press(.playPause)
        XCTAssertTrue(player.waitFor("hidden"))
        sleep(1)
        XCTAssertFalse(player.isPaused)
        XCTAssertGreaterThanOrEqual(player.seconds, origin + 20)

        // Paused from Play/Pause, a cancelled scrub stays paused.
        remote.press(.playPause)
        sleep(1)
        XCTAssertTrue(player.isPaused)
        XCTAssertTrue(app.descendants(matching: .any)["pausedPill"].waitForExistence(timeout: 2))
        remote.press(.select)
        XCTAssertTrue(player.waitFor("scrubbing"))
        remote.press(.menu)
        XCTAssertTrue(player.waitFor("hidden"))
        sleep(1)
        XCTAssertTrue(player.isPaused, "Back should put back what the click found")

        // The bar's main button does what a click does.
        remote.press(.up)
        XCTAssertTrue(player.waitFor("bar"))
        XCTAssertTrue(player.waitFor("focus main"))
        remote.press(.select)
        XCTAssertTrue(player.waitFor("scrubbing"))
        remote.press(.select)
        XCTAssertTrue(player.waitFor("hidden"))
        sleep(1)
        XCTAssertFalse(player.isPaused)
    }

    func testTracksSpeedPictureAndInfo() throws {
        openPlayer()

        player.openPanel("audio")
        capture("options-audio")
        XCTAssertTrue(app.buttons["audio-1"].isSelected)
        press(.down)
        remote.press(.select)
        sleep(1)
        XCTAssertTrue(app.buttons["audio-2"].isSelected, "Down and select should pick the second track")
        press(.menu)

        // A subtitle AVPlayer can show stays there, and one only mpv can show moves there.
        player.openPanel("subtitles")
        capture("options-subtitles")
        XCTAssertTrue(app.buttons["subtitle-off"].isSelected)
        press(.down)
        remote.press(.select)
        sleep(1)
        XCTAssertTrue(app.buttons["subtitle-3"].isSelected)
        XCTAssertTrue(engineLabel().contains("avPlayer"), engineLabel())
        press(.down)
        remote.press(.select)
        sleep(2)
        XCTAssertTrue(app.buttons["subtitle-4"].isSelected)
        XCTAssertTrue(engineLabel().contains("mpv"), "PGS should move to mpv: \(engineLabel())")
        press(.menu)

        player.openPanel("playback")
        capture("options-picture-speed")
        press(.down, times: 2)
        remote.press(.select)
        sleep(1)
        XCTAssertFalse(app.buttons["rate-1.0"].isSelected, "Another speed should be chosen")
        press(.down, times: 3)
        remote.press(.select)
        sleep(1)
        XCTAssertFalse(app.buttons["picture-fit"].isSelected, "Another picture mode should be chosen")
        press(.menu)

        player.openPanel("info")
        capture("options-info")
        let info = app.buttons["infoRows"].label
        XCTAssertTrue(info.contains("mpv"), info)
        XCTAssertTrue(info.contains("French PGS"), info)
        player.closePanelToNothing()
        XCTAssertTrue(player.isShowing("hidden"))
    }

    /// The timing options are the ones AVPlayer can't do, so they say so and move.
    func testTimingOptionsMoveToMpvAndSizeStays() throws {
        openPlayer()
        XCTAssertTrue(engineLabel().contains("avPlayer"), engineLabel())

        player.openPanel("subtitles")
        XCTAssertTrue(app.descendants(matching: .any)["subtitleDelay-note"].exists, "Should warn before moving")
        // Off, two tracks, then Offset.
        press(.down, times: 3)
        press(.right)
        remote.press(.select)
        sleep(2)
        capture("options-subtitle-offset")
        XCTAssertEqual(value("subtitleDelay"), "+0.1 s")
        XCTAssertTrue(engineLabel().contains("mpv"), "An offset should move to mpv: \(engineLabel())")
        XCTAssertFalse(app.descendants(matching: .any)["subtitleDelay-note"].exists, "Nothing left to warn about")
        press(.menu)

        player.openPanel("audio")
        press(.down, times: 2)
        press(.right)
        remote.press(.select)
        sleep(1)
        XCTAssertEqual(value("audioDelay"), "+0.1 s")
        XCTAssertTrue(engineLabel().contains("mpv"))
        player.closePanelToNothing()
    }

    func testSubtitleSizeAndPositionSurviveARelaunch() throws {
        openPlayer()
        player.openPanel("subtitles")
        // Off, two tracks, Offset, then Size and Position.
        press(.down, times: 4)
        press(.right)
        remote.press(.select)
        sleep(1)
        XCTAssertEqual(value("subtitleSize"), "110%")
        press(.down)
        remote.press(.select)
        sleep(1)
        XCTAssertEqual(value("subtitlePosition"), "Up 5%")
        capture("options-subtitle-style")
        XCTAssertTrue(engineLabel().contains("avPlayer"), "Size and position shouldn't move engines")
        player.closePanelToNothing()

        app.terminate()
        openPlayer("-FinesseSeededKeepPreferences")
        player.openPanel("subtitles")
        XCTAssertEqual(value("subtitleSize"), "110%")
        XCTAssertEqual(value("subtitlePosition"), "Up 5%")
    }

    /// Pure white and pure black are harder on the glass than any real frame.
    func testReadableOverBrightAndDarkFrames() throws {
        for (name, argument) in [("bright", "-FinesseSeededBrightFrame"), ("dark", "-FinesseSeededDarkFrame")] {
            openPlayer(argument)
            remote.press(.up)
            XCTAssertTrue(player.waitFor("bar"))
            sleep(1)
            capture("frame-\(name)-bar")
            player.openPanel("subtitles")
            sleep(1)
            capture("frame-\(name)-panel")
            player.closePanelToNothing()
            remote.press(.select)
            XCTAssertTrue(player.waitFor("scrubbing"))
            press(.right, times: 4)
            capture("frame-\(name)-scrub")
            remote.press(.menu)
            XCTAssertTrue(player.waitFor("hidden"))
            remote.press(.playPause)
            sleep(1)
            capture("frame-\(name)-paused")
            app.terminate()
        }
    }

    func testQualityMovesToATranscodeAndDisablesTimingOptions() throws {
        openPlayer()
        player.openPanel("quality")
        capture("options-quality")
        XCTAssertTrue(app.buttons["bitrate-0"].isSelected, "Original should be selected")
        // Original, 40, 20, 10, 8, then 4 Mbps, which is under the seeded 5 Mbps file.
        press(.down, times: 5)
        remote.press(.select)
        sleep(2)
        XCTAssertTrue(app.buttons["bitrate-4000000"].isSelected)
        press(.menu)

        player.openPanel("info")
        XCTAssertTrue(app.buttons["infoRows"].label.contains("Converted by the server"), app.buttons["infoRows"].label)
        press(.menu)

        player.openPanel("audio")
        let note = app.descendants(matching: .any)["audioDelay-note"]
        XCTAssertTrue(note.exists)
        XCTAssertTrue(note.label.contains("converting"), note.label)
        capture("options-delay-disabled")
        press(.menu)

        // Back to Original goes direct again.
        player.openPanel("quality")
        press(.up, times: 5)
        remote.press(.select)
        sleep(2)
        XCTAssertTrue(app.buttons["bitrate-0"].isSelected)
    }

    func testASavedLimitThatCantPlayOffersAWayOut() throws {
        continueAfterFailure = false
        app.launchArguments = ["-FinesseFakeServer", "-FinesseSeededPlayback", "-FinesseSeededNoSegments", "-FinesseSeededStuckOnLimit"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        sleep(1)
        focusFirstHomeCard(in: app)
        remote.press(.select)
        let play = app.buttons["detailPlay"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        sleep(1)
        remote.press(.select)

        let wayOut = app.buttons["removeQualityLimit"]
        XCTAssertTrue(wayOut.waitForExistence(timeout: 15), "The failure should offer a way out of the limit")
        sleep(1)
        capture("options-stuck-on-limit")
        remote.press(.down)
        sleep(1)
        remote.press(.select)
        XCTAssertTrue(player.bar.waitForExistence(timeout: 15), "Should now play")
        XCTAssertFalse(wayOut.exists)
    }

    func testChaptersSeekAndHideTheControls() throws {
        openPlayer()
        player.openPanel("chapters")
        capture("options-chapters")
        press(.down)
        remote.press(.select)
        XCTAssertTrue(player.waitFor("hidden"), "Choosing a chapter should hide the controls")
        sleep(1)
        XCTAssertGreaterThanOrEqual(player.seconds, 600)
        XCTAssertFalse(player.isPaused)
    }

    func testEpisodesPreviousAndNext() throws {
        openPlayer(onNextUp: true)
        XCTAssertTrue(player.isShowing("hidden"))
        remote.press(.up)
        XCTAssertTrue(player.waitFor("focus main"))
        XCTAssertTrue(app.buttons["hudPrevious"].exists)
        XCTAssertTrue(app.buttons["hudNext"].exists)
        capture("options-bar-on-an-episode")

        press(.right)
        remote.press(.select)
        XCTAssertTrue(player.bar.waitForExistence(timeout: 10))
        XCTAssertTrue(player.waitFor("hidden", timeout: 10), "Next should start with nothing showing")
        sleep(1)

        player.openPanel("episodes")
        capture("options-episodes")
        XCTAssertTrue(app.buttons["episode-seeded-episode-3"].isSelected, "The next episode should be current")
        press(.up)
        remote.press(.select)
        XCTAssertTrue(player.waitFor("hidden", timeout: 10))
        sleep(1)
        player.openPanel("episodes")
        XCTAssertFalse(app.buttons["episode-seeded-episode-3"].isSelected, "Choosing should change episode")
    }
}
