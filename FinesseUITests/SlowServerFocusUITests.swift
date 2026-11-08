import XCTest

/// Every screen on a slow server, where a loading view shows first. Focus must land on the new
/// screen once it loads, and never stay on a screen that's hidden underneath, where the remote would
/// act unseen. Uses the fake server with every request held for 1.5 seconds.
@MainActor
final class SlowServerFocusUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication()

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    private func launch() {
        continueAfterFailure = false
        app.launchArguments = ["-FinesseFakeServer", "-FinesseFakeServerDelay", "1.5"]
        app.launch()
        XCTAssertTrue(app.buttons["heroPlay"].waitForExistence(timeout: 60))
        sleep(2)
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            sleep(1)
            note("after remote button \(button.rawValue)")
        }
    }

    /// Where focus is, for reading a failure from the log.
    private func note(_ step: String) {
        let element = focused
        print("SLOWFOCUS \(step): " + (element.exists ? "\(element.identifier) '\(element.label)'" : "nothing focused"))
    }

    /// Opens the card that `downs` presses from the tab bar reach, and waits for its page to load.
    private func openDetail(downs: Int, expecting title: String, line: UInt = #line) {
        press(.down, times: downs)
        // Nothing reports focus while it's moving between cards, so give it a moment to settle.
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true AND label == %@", title)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Should be on the card for \(title)", line: line)
        remote.press(.select)
        let actions = app.buttons.matching(NSPredicate(format: "identifier IN %@", ["detailPlay", "detailWatched"]))
        XCTAssertFalse(actions.firstMatch.waitForExistence(timeout: 1), "The delay should show the loading view first", line: line)
        XCTAssertTrue(app.buttons["detailWatched"].waitForExistence(timeout: 30), line: line)
        sleep(2)
    }

    private func expectFocusOnPlay(_ page: String, line: UInt = #line) {
        XCTAssertEqual(focused.identifier, "detailPlay", "\(page): Play should have focus once the page loads", line: line)
        capture("slow-\(page)-loaded")
        // Up stays on this page instead of acting on the screen underneath.
        press(.up)
        XCTAssertTrue(app.buttons["detailPlay"].exists, "\(page): Up should not leave the page", line: line)
        remote.press(.menu)
        XCTAssertTrue(app.buttons["detailWatched"].waitForNonExistence(timeout: 10), "\(page): Back should leave the page", line: line)
        sleep(3)
    }

    func testMovieEpisodeAndShowPagesFocusPlayOnceLoaded() throws {
        launch()
        openDetail(downs: 2, expecting: "A Film in Progress")
        expectFocusOnPlay("movie")

        press(.menu)
        press(.menu)
        openDetail(downs: 3, expecting: "A Long Show")
        expectFocusOnPlay("episode")

        press(.menu)
        press(.menu)
        openDetail(downs: 5, expecting: "A Long Show")
        expectFocusOnPlay("show")
    }

    /// Back while the page is still loading leaves it, and focus is back on the card it came from.
    func testBackWhileLoadingReturnsToTheCard() throws {
        launch()
        press(.down, times: 2)
        let card = focused.label
        XCTAssertEqual(card, "A Film in Progress")
        remote.press(.select)
        usleep(800_000)
        XCTAssertFalse(app.buttons["detailWatched"].exists, "Still loading")
        remote.press(.menu)
        sleep(5)
        XCTAssertFalse(app.buttons["detailWatched"].exists, "Back should have left the page before it loaded")
        XCTAssertEqual(focused.label, card, "Focus should be back on the card")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Tab roots keep focus on the tab bar while they load, then the content can be reached.
    func testLibraryGridAndSearchCanBeReachedOnceLoaded() throws {
        launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].hasFocus)
        press(.right)
        XCTAssertTrue(app.tabBars.buttons["Movies"].hasFocus)
        remote.press(.select)
        XCTAssertTrue(app.buttons["librarySort"].waitForExistence(timeout: 30))
        sleep(3)
        XCTAssertTrue(focused.exists, "Something should have focus on the loaded grid")
        press(.down, times: 2)
        XCTAssertTrue(focused.exists && !app.tabBars.buttons[focused.label].exists, "Down should reach the grid")
        capture("slow-movies-grid")

        press(.up, times: 6)
        press(.right, times: 2)
        XCTAssertTrue(app.tabBars.buttons["Search"].hasFocus)
        remote.press(.select)
        sleep(2)
        press(.down)
        app.typeText("Film")
        sleep(6)
        XCTAssertTrue(app.staticTexts["Movies"].waitForExistence(timeout: 20), "Search should show results")
        press(.down, times: 4)
        XCTAssertTrue(focused.label.contains("Film"), "Down should reach a result, not \(focused.label)")
        capture("slow-search-results")
        remote.press(.select)
        XCTAssertTrue(app.buttons["detailWatched"].waitForExistence(timeout: 30))
        sleep(2)
        XCTAssertTrue(["detailPlay", "detailWatched"].contains(focused.identifier), "A page opened from Search should take focus")
    }
}
