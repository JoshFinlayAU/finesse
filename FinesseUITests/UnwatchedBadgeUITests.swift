import XCTest

/// The unwatched-episode count on show posters, on the fake server, where "A Long Show" has 12 left.
/// The badge itself is hidden from accessibility, so this reads the count from the card's value.
@MainActor
final class UnwatchedBadgeUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication()

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    private var focusedValue: String { (focused.value as? String) ?? "" }

    private func openTab(right presses: Int) {
        for _ in 0..<presses {
            remote.press(.right)
            usleep(500_000)
        }
        remote.press(.select)
        XCTAssertTrue(app.buttons["librarySort"].waitForExistence(timeout: 20))
        sleep(2)
        remote.press(.down)
        sleep(1)
    }

    func testShowPostersCountUnwatchedEpisodesAndFilmsDont() throws {
        continueAfterFailure = false
        app.launchArguments = ["-FinesseFakeServer"]
        app.launch()
        XCTAssertTrue(app.buttons["heroPlay"].waitForExistence(timeout: 30))
        sleep(2)
        XCTAssertTrue(app.tabBars.buttons["Home"].hasFocus)

        // A film's poster has no count.
        openTab(right: 1)
        XCTAssertFalse(focused.label.isEmpty, "A film should have focus")
        XCTAssertFalse(focusedValue.contains("unwatched"), "Films have no count: \(focusedValue)")

        // The show's poster says how many episodes are left.
        remote.press(.menu)
        sleep(1)
        openTab(right: 1)
        XCTAssertEqual(focused.label, "A Long Show")
        XCTAssertTrue(focusedValue.contains("12 unwatched episodes"), "The show should count what's left: \(focusedValue)")
        capture("badge-tv-shows-grid")
    }
}
