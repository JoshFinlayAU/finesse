import XCTest

/// Runs against the app's built-in fake server, with two signed-in users and seeded hubs.
@MainActor
final class FakeServerUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication()

    private func launch() {
        continueAfterFailure = false
        app.launchArguments = ["-FinesseFakeServer"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        sleep(1)
    }

    func testSwitchUsersWithoutSigningIn() throws {
        launch()
        capture("fake-1-home")
        openSettings()
        capture("fake-2-settings-alice-current")

        let bob = app.buttons["account-Bob"]
        XCTAssertTrue(bob.waitForExistence(timeout: 10))
        focus(bob, in: app)
        remote.press(.select)

        // No password step: straight back to Home, then Settings shows Bob as current.
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
        sleep(1)
        openSettings()
        XCTAssertTrue(app.buttons["Sign Out Bob"].exists || app.staticTexts["Sign Out Bob"].exists)
        capture("fake-3-settings-bob-current")

        // Sign out Bob: Alice's token is still held, so she is offered with no password.
        focus(app.buttons["signOut"], in: app)
        remote.press(.select)
        let alice = app.buttons["user-Alice"]
        XCTAssertTrue(alice.waitForExistence(timeout: 20))
        capture("fake-4-picker-with-held-user")
        focus(alice, in: app)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
    }

    func testHomeBackMenuAndPlayPaths() throws {
        launch()

        // Tab bar to the first row. Select goes to Detail, Menu comes back with focus on the row.
        remote.press(.down)
        sleep(1)
        capture("fake-5-card-focused")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["A Film in Progress"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))
        capture("fake-6-detail")
        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 10))
        sleep(1)
        capture("fake-7-back-on-home")

        // Play/Pause on a card resumes straight away, and Menu leaves the player.
        remote.press(.playPause)
        XCTAssertTrue(app.staticTexts["Player not built yet. Resume at 1500 seconds."].waitForExistence(timeout: 10))
        capture("fake-8-player")
        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 10))

        // Long press shows the actions menu.
        sleep(1)
        capture("fake-9a-before-long-press")
        remote.press(.select, forDuration: 2)
        sleep(2)
        capture("fake-9-context-menu")
        XCTAssertTrue(app.descendants(matching: .any)["Resume"].waitForExistence(timeout: 10))
        remote.press(.menu)
        sleep(1)

        // Down to each row in turn, then Menu returns to the tab bar.
        remote.press(.down)
        sleep(1)
        remote.press(.down)
        sleep(1)
        capture("fake-10-recently-added")
        remote.press(.menu)
        sleep(1)
        capture("fake-11-menu-to-tab-bar")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Up to the tab bar from wherever focus is, then across to Settings.
    private func openSettings() {
        focus(app.tabBars.buttons["Home"], in: app)
        for _ in 0..<4 {
            remote.press(.right)
            usleep(500_000)
        }
        remote.press(.select)
        XCTAssertTrue(app.buttons["signOut"].waitForExistence(timeout: 10))
        sleep(1)
    }
}
