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

    func testOneClickSkipsOnceTheControlsHideDuringASegment() throws {
        openPlayer()
        let bar = app.buttons["transportBar"]
        let skip = app.buttons["skipSegment"]
        XCTAssertTrue(bar.waitForExistence(timeout: 15))
        let start = seconds(bar) - 2
        XCTAssertTrue(skip.waitForExistence(timeout: 12))
        // Appeared with the controls up. Wait for them to hide while the segment is still running.
        sleep(4)
        capture("skip-11-controls-hid-during-intro")
        XCTAssertTrue(skip.exists, "The intro should still be running")
        remote.press(.select)
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5), "One click should skip, not just show the controls")
        XCTAssertGreaterThanOrEqual(seconds(bar), start + 14)
        XCTAssertFalse(isPaused(bar))
    }

    func testSeededSkipButtonsAppearSkipAndGoAway() throws {
        openPlayer()
        let bar = app.buttons["transportBar"]
        let skip = app.buttons["skipSegment"]
        XCTAssertTrue(bar.waitForExistence(timeout: 15))
        // Playback started a moment before the bar could be read, so allow for that.
        let start = seconds(bar) - 2
        XCTAssertFalse(skip.exists, "No button before the segment starts")
        capture("skip-1-before-intro")

        // Skip Intro appears with the controls up, and it can wait there while playback carries on.
        XCTAssertTrue(skip.waitForExistence(timeout: 12), "Skip Intro should appear inside the intro")
        XCTAssertEqual(skip.label, "Skip Intro")
        capture("skip-2-intro")
        let inIntro = seconds(bar)
        sleep(2)
        XCTAssertGreaterThan(seconds(bar), inIntro, "The button must not interrupt playback")
        XCTAssertFalse(isPaused(bar))

        // Reaching it and pressing it goes to the end of the intro, and it goes away.
        remote.press(.up)
        sleep(1)
        capture("skip-3-intro-focused")
        XCTAssertGreaterThan(seconds(bar), inIntro, "Focusing the button must not stop playback")
        XCTAssertFalse(isPaused(bar))
        remote.press(.select)
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5), "The button should go once used")
        XCTAssertGreaterThanOrEqual(seconds(bar), start + 14, "Should land at the end of the intro")
        XCTAssertFalse(isPaused(bar), "Skipping should not pause")
        capture("skip-4-after-intro")

        // With the controls hidden, Skip Credits takes focus by itself, so one press is enough.
        XCTAssertTrue(skip.waitForExistence(timeout: 15), "Skip Credits should appear inside the credits")
        XCTAssertEqual(skip.label, "Skip Credits")
        sleep(1)
        capture("skip-5-credits-controls-hidden")
        XCTAssertFalse(isPaused(bar))
        remote.press(.select)
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(seconds(bar), start + 30, "Should land at the end of the credits")
        XCTAssertFalse(isPaused(bar))
        capture("skip-6-after-credits")

        // Left alone, a button leaves when its segment ends, and playback never stopped.
        XCTAssertTrue(skip.waitForExistence(timeout: 15), "The third segment's button should appear")
        capture("skip-7-left-alone")
        XCTAssertTrue(skip.waitForNonExistence(timeout: 10), "It should go when the segment ends")
        XCTAssertGreaterThanOrEqual(seconds(bar), start + 46)
        XCTAssertFalse(isPaused(bar))
        capture("skip-8-segment-passed")

        // Focus is back on the bar: select brings the controls up rather than doing nothing.
        remote.press(.select)
        sleep(1)
        capture("skip-9-controls-back")
        XCTAssertFalse(isPaused(bar), "The first select on hidden controls should only show them")
        remote.press(.select)
        sleep(1)
        XCTAssertTrue(isPaused(bar), "The bar should have focus again")
        remote.press(.playPause)
        sleep(1)

        // Back still leaves the player.
        remote.press(.menu)
        sleep(1)
        remote.press(.menu)
        XCTAssertTrue(bar.waitForNonExistence(timeout: 15), "Back should leave the player")
        capture("skip-10-back-on-detail")
    }
}
