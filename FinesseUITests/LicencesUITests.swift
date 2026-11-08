import XCTest

/// Settings > Licences on the built-in fake server, which needs no test server.
@MainActor
final class LicencesUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication()

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    func testListLongTextAndBackPath() throws {
        continueAfterFailure = false
        app.launchArguments = ["-FinesseFakeServer"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        sleep(1)

        // Settings tab, then down to the Licences row.
        focus(app.tabBars.buttons["Home"], in: app)
        for _ in 0..<4 {
            remote.press(.right)
            usleep(500_000)
        }
        remote.press(.select)
        let row = app.buttons["licences"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        focus(row, in: app)
        capture("licences-1-settings-row")
        remote.press(.select)

        // The list, starting with where to get the source.
        let offer = app.descendants(matching: .any)["sourceOffer"]
        XCTAssertTrue(offer.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["licence-finesse"].exists, "Finesse lists its own licence")
        sleep(1)
        capture("licences-2-list")

        // Down to FFmpeg, whose licence is the longest in the app.
        let ffmpeg = app.buttons["licence-ffmpeg"]
        XCTAssertTrue(ffmpeg.waitForExistence(timeout: 10))
        focus(ffmpeg, in: app)
        capture("licences-3-ffmpeg-row")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Version 8.1.3"].waitForExistence(timeout: 10))
        sleep(2)
        capture("licences-4-ffmpeg-top")

        // Each press moves focus to the next piece of text, so the page really scrolls.
        let first = focused.label
        XCTAssertTrue(first.contains("GNU LESSER GENERAL PUBLIC LICENSE"), "Focus should start on the licence text")
        for _ in 0..<6 {
            remote.press(.down)
            usleep(600_000)
        }
        let later = focused.label
        XCTAssertNotEqual(later, first, "Down should move through the text")
        sleep(1)
        capture("licences-5-ffmpeg-further-down")

        // All the way into the second licence, to prove nothing stops part way. Each press waits
        // for focus to land on the next piece, so a slow simulator can't drop presses mid-scroll.
        let gpl = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true AND label CONTAINS %@", "GNU GENERAL PUBLIC LICENSE")).firstMatch
        var current = later
        var stuck = 0
        for _ in 0..<150 where stuck < 3 && !gpl.exists {
            remote.press(.down)
            let next = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == true AND label != %@", current)).firstMatch
            if next.waitForExistence(timeout: 3) {
                current = next.label
                stuck = 0
            } else {
                stuck += 1
            }
        }
        XCTAssertTrue(gpl.exists, "Down should reach the GPL text after the LGPL, but stopped on: \(current.prefix(80))")
        sleep(1)
        capture("licences-6-gpl-text")

        // Back: licence to list, list to Settings, Settings to the tab bar.
        remote.press(.menu)
        XCTAssertTrue(offer.waitForExistence(timeout: 10))
        sleep(1)
        XCTAssertTrue(ffmpeg.waitForExistence(timeout: 5))
        capture("licences-7-back-on-list")
        remote.press(.menu)
        XCTAssertTrue(app.buttons["signOut"].waitForExistence(timeout: 10))
        sleep(1)
        capture("licences-8-back-on-settings")
        remote.press(.menu)
        sleep(1)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }
}
