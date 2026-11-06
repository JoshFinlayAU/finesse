import XCTest

/// Shows the skip buttons on screen. This is seeded: the segments are made up by a DEBUG launch
/// flag and the engine plays nothing, because the test server has no segments. Server-provided
/// segments and the buttons over real video remain untested.
@MainActor
final class SkipSegmentUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication()

    private func seconds(_ bar: XCUIElement) -> Int {
        let value = (bar.value as? String) ?? ""
        let time = value.split(separator: ",").first.map(String.init) ?? ""
        return time.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    private func isPaused(_ bar: XCUIElement) -> Bool {
        (bar.value as? String)?.contains("paused") == true
    }

    private func openPlayer() {
        continueAfterFailure = false
        app.launchArguments = ["-FinesseFakeServer", "-FinesseSeededPlayback"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        sleep(1)

        // Home, the resume card, then Resume on Detail.
        let play = app.buttons["detailPlay"]
        for _ in 0..<4 where !play.exists {
            remote.press(.select)
            sleep(2)
            if !play.exists {
                remote.press(.down)
                sleep(1)
            }
        }
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        sleep(1)
        remote.press(.select)
    }

    /// The segment's button holds focus with nothing else showing, so the click skips and doesn't pause.
    func testOneClickSkipsInsideASegmentAndDoesNotPause() throws {
        openPlayer()
        let bar = app.buttons["transportBar"]
        let skip = app.buttons["skipSegment"]
        XCTAssertTrue(bar.waitForExistence(timeout: 15))
        let start = seconds(bar) - 2
        XCTAssertTrue(skip.waitForExistence(timeout: 12))
        sleep(1)
        capture("skip-1-intro")
        remote.press(.select)
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5), "One click should skip")
        XCTAssertGreaterThanOrEqual(seconds(bar), start + 14)
        XCTAssertFalse(isPaused(bar))
        XCTAssertFalse((bar.value as? String)?.contains("scrubbing") == true)
    }

    func testSwipeUpDuringASegmentLeavesTheButtonReachableAndItsFocusComesBack() throws {
        openPlayer()
        let player = PlayerDriver(app: app)
        let skip = app.buttons["skipSegment"]
        XCTAssertTrue(player.bar.waitForExistence(timeout: 15))
        XCTAssertTrue(skip.waitForExistence(timeout: 12))
        sleep(1)

        // Up opens the bar even with the button focused, and takes focus to the bar.
        remote.press(.up)
        XCTAssertTrue(player.waitFor("bar"), "Up should show the bar during a segment")
        XCTAssertTrue(player.waitFor("focus main"), "The bar should take focus")
        XCTAssertTrue(skip.exists, "The button should stay")
        capture("skip-2-bar-over-segment")

        // Back hands focus back to the button, which still takes one click.
        remote.press(.menu)
        XCTAssertTrue(player.waitFor("hidden"))
        XCTAssertTrue(player.waitFor("focus skip"), "The button should have focus again")
        remote.press(.select)
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        XCTAssertFalse(isPaused(player.bar))
    }

    func testSeededSkipButtonsAppearSkipAndGoAway() throws {
        openPlayer()
        let bar = app.buttons["transportBar"]
        let skip = app.buttons["skipSegment"]
        XCTAssertTrue(bar.waitForExistence(timeout: 15))
        // Playback started a moment before the bar could be read, so allow for that.
        let start = seconds(bar) - 2
        XCTAssertFalse(skip.exists, "No button before the segment starts")
        capture("skip-3-before-intro")

        XCTAssertTrue(skip.waitForExistence(timeout: 12), "Skip Intro should appear inside the intro")
        XCTAssertEqual(skip.label, "Skip Intro")
        let inIntro = seconds(bar)
        sleep(2)
        XCTAssertGreaterThan(seconds(bar), inIntro, "The button must not interrupt playback")
        XCTAssertFalse(isPaused(bar))

        remote.press(.select)
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5), "The button should go once used")
        XCTAssertGreaterThanOrEqual(seconds(bar), start + 14, "Should land at the end of the intro")
        XCTAssertFalse(isPaused(bar), "Skipping should not pause")

        XCTAssertTrue(skip.waitForExistence(timeout: 15), "Skip Credits should appear inside the credits")
        XCTAssertEqual(skip.label, "Skip Credits")
        sleep(1)
        capture("skip-4-credits")
        remote.press(.select)
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(seconds(bar), start + 30, "Should land at the end of the credits")
        XCTAssertFalse(isPaused(bar))

        // Left alone, a button leaves when its segment ends, and playback never stopped.
        XCTAssertTrue(skip.waitForExistence(timeout: 15), "The third segment's button should appear")
        XCTAssertTrue(skip.waitForNonExistence(timeout: 10), "It should go when the segment ends")
        XCTAssertGreaterThanOrEqual(seconds(bar), start + 46)
        XCTAssertFalse(isPaused(bar))
        capture("skip-5-segment-passed")

        // Focus is back on the surface, so a click now pauses and starts a scrub.
        sleep(1)
        remote.press(.select)
        sleep(1)
        XCTAssertTrue(isPaused(bar), "The surface should have focus again")
        XCTAssertTrue((bar.value as? String)?.contains("scrubbing") == true)
        remote.press(.menu)
        sleep(1)

        remote.press(.menu)
        XCTAssertTrue(bar.waitForNonExistence(timeout: 15), "Back should leave the player")
    }
}
