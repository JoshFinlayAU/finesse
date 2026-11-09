import XCTest

/// A screen that's open updates itself when the server says something changed. The fake server
/// adds an episode of A Long Show a set time after launch, as a library scan would, and the
/// TV Shows grid shows the new count with no key pressed.
@MainActor
final class LiveUpdatesUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private let app = XCUIApplication()

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            usleep(500_000)
        }
    }

    private func card(counting text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ AND value CONTAINS %@", "A Long Show", text))
            .firstMatch
    }

    func testANewEpisodeShowsUpWithoutNavigating() throws {
        continueAfterFailure = false
        app.launchArguments = ["-FinesseFakeServer", "-FinesseFakeServerNewEpisodeAfter", "30"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["heroMoreInfo"].waitForExistence(timeout: 30))
        sleep(3)

        // TV Shows, from the tab bar.
        press(.up, times: 4)
        press(.left, times: 5)
        press(.right, times: 2)
        remote.press(.select)
        let show = card(counting: "12 unwatched episodes")
        XCTAssertTrue(show.waitForExistence(timeout: 20), "TV Shows should list A Long Show with 12 episodes left")
        capture("live-1-before")

        // No more presses from here. The episode arrives about 30 seconds after launch.
        XCTAssertTrue(card(counting: "13 unwatched episodes").waitForExistence(timeout: 60), "The new episode should show without navigating")
        capture("live-2-after")
        XCTAssertTrue(app.staticTexts["TV Shows"].exists, "Still on TV Shows")
    }
}
