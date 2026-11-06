import XCTest

/// Shows the move between engines in the real player. This is seeded: the engines play nothing and
/// fail on request. A real AVPlayer failure is covered by `avPlayerFailingForRealMovesToMpvAtThePosition`
/// in the integration tests, which has no UI.
@MainActor
final class EngineFailureUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication()

    private func seconds(_ bar: XCUIElement) -> Int {
        let time = ((bar.value as? String) ?? "").split(separator: ",").first.map(String.init) ?? ""
        return time.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    private func openPlayer(failure: String) {
        continueAfterFailure = false
        app.launchArguments = ["-FinesseFakeServer", "-FinesseSeededPlayback", failure]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        sleep(1)
        focusFirstHomeCard(in: app)
        remote.press(.select)
        let play = app.buttons["detailPlay"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        sleep(1)
        remote.press(.select)
    }

    private func engineLabel() -> String {
        app.descendants(matching: .any)["seededEngine"].label
    }

    func testAVPlayerFailingCarriesOnOnMpvWithNoError() throws {
        openPlayer(failure: "-FinesseSeededAVPlayerFails")
        let bar = app.buttons["transportBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 15))
        XCTAssertTrue(engineLabel().contains("avPlayer"), engineLabel())
        capture("failure-1-on-avplayer")

        // Fails 3 seconds in. Polled, because the point is that nothing else appears on the way.
        let deadline = Date.now.addingTimeInterval(10)
        while !engineLabel().contains("mpv"), Date.now < deadline {
            XCTAssertFalse(app.staticTexts["Something Went Wrong"].exists, "No error while mpv can take over")
            usleep(250_000)
        }
        XCTAssertTrue(engineLabel().contains("mpv"), engineLabel())
        let moved = seconds(bar)
        XCTAssertGreaterThanOrEqual(moved, 2, "Should carry on from where it was, not the start")
        capture("failure-2-on-mpv")

        sleep(4)
        XCTAssertGreaterThan(seconds(bar), moved, "mpv should be playing")
        XCTAssertFalse(app.staticTexts["Something Went Wrong"].exists)
        XCTAssertTrue(engineLabel().contains("mpv"), "Should stay on mpv, not go back")
        capture("failure-3-still-on-mpv")

        remote.press(.up)
        sleep(1)
        remote.press(.menu)
        sleep(1)
        remote.press(.menu)
        XCTAssertTrue(bar.waitForNonExistence(timeout: 15), "Back should leave the player")
    }

    func testTheErrorShowsOnlyOnceBothEnginesHaveFailed() throws {
        openPlayer(failure: "-FinesseSeededBothFail")
        let bar = app.buttons["transportBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Something Went Wrong"].exists)

        let error = app.staticTexts["Something Went Wrong"]
        XCTAssertTrue(error.waitForExistence(timeout: 15), "Both engines failing should show the error")
        XCTAssertFalse(bar.exists)
        // It stays put rather than bouncing between engines.
        sleep(5)
        XCTAssertTrue(error.exists)
        XCTAssertFalse(bar.exists)
        capture("failure-4-both-failed")

        remote.press(.menu)
        XCTAssertTrue(error.waitForNonExistence(timeout: 15), "Back should leave the error")
        XCTAssertTrue(app.buttons["detailPlay"].waitForExistence(timeout: 10))
        capture("failure-5-back-on-detail")
    }
}
