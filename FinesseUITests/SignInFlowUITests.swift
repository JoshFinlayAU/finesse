import XCTest

/// Drives the real app with the Siri Remote API against the test server, and keeps a screenshot
/// of each screen. Skips without credentials. Reset the simulator keychain first, so it starts signed out.
@MainActor
final class SignInFlowUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication.forSignIn()

    private func environment(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name] else {
            throw XCTSkip("\(name) is not set")
        }
        return value
    }

    func testSignInHomeBackPathAndSignOut() throws {
        let server = try environment("JELLYFIN_URL")
        let username = try environment("JELLYFIN_USERNAME")
        _ = try environment("JELLYFIN_PASSWORD")
        continueAfterFailure = false
        app.launch()

        // Server address.
        let address = app.textFields["serverAddress"]
        XCTAssertTrue(address.waitForExistence(timeout: 20))
        capture("1-server-entry")
        enter(server, into: address, in: app)
        focus(app.buttons["connect"], in: app)
        remote.press(.select)

        // User picker. The hidden test user isn't listed, so use Other User.
        let other = app.buttons["otherUser"]
        XCTAssertTrue(other.waitForExistence(timeout: 20))

        // Back from the picker returns to the server step, with the address kept.
        remote.press(.menu)
        XCTAssertTrue(app.buttons["connect"].waitForExistence(timeout: 10))
        focus(app.buttons["connect"], in: app)
        remote.press(.select)
        XCTAssertTrue(other.waitForExistence(timeout: 20))

        focus(other, in: app)
        remote.press(.select)
        let usernameField = app.textFields["username"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 10))
        enter(username, into: usernameField, in: app)
        let passwordField = app.secureTextFields["password"]
        enter("definitely-wrong", into: passwordField, in: app)
        focus(app.buttons["signIn"], in: app)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Incorrect username or password."].waitForExistence(timeout: 20))
        capture("3-wrong-password")

        enter(TypedPassword.first, into: passwordField, in: app)
        focus(app.buttons["signIn"], in: app)
        remote.press(.select)

        // Home.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30))
        // Rows below the fold don't exist yet, so wait for whichever hub comes first.
        let firstHub = app.staticTexts.matching(
            NSPredicate(format: "label IN %@", ["Continue Watching", "Next Up", "Recently Added"])
        ).firstMatch
        XCTAssertTrue(firstHub.waitForExistence(timeout: 30))
        sleep(4)
        capture("4-home")

        // Select a card, then Menu comes back to Home with its rows still there.
        remote.press(.down)
        sleep(1)
        capture("5-home-focused")
        remote.press(.select)
        sleep(2)
        capture("6-detail-route")
        remote.press(.menu)
        XCTAssertTrue(firstHub.waitForExistence(timeout: 10))
        sleep(1)
        capture("7-back-on-home")

        // Relaunch restores the session with no sign-in.
        app.terminate()
        app.launch()
        XCTAssertTrue(firstHub.waitForExistence(timeout: 30))

        // Settings, then sign out.
        sleep(1)
        focus(app.tabBars.buttons["Home"], in: app)
        for _ in 0..<4 {
            remote.press(.right)
            usleep(500_000)
        }
        remote.press(.select)
        let signOut = app.buttons["signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 10))
        sleep(1)
        capture("8-settings")
        focus(signOut, in: app)
        remote.press(.select)
        XCTAssertTrue(app.buttons["otherUser"].waitForExistence(timeout: 20))
    }

    func testQuickConnectShowsCodeAndBackLeaves() throws {
        let server = try environment("JELLYFIN_URL")
        continueAfterFailure = false
        app.launch()
        let address = app.textFields["serverAddress"]
        XCTAssertTrue(address.waitForExistence(timeout: 20))
        enter(server, into: address, in: app)
        focus(app.buttons["connect"], in: app)
        remote.press(.select)
        let quickConnect = app.buttons["quickConnect"]
        XCTAssertTrue(quickConnect.waitForExistence(timeout: 20))
        focus(quickConnect, in: app)
        remote.press(.select)
        let code = app.staticTexts["quickConnectCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 20))
        capture("quick-connect")

        // Back cancels the wait, and coming back starts a new code.
        remote.press(.menu)
        XCTAssertTrue(app.buttons["otherUser"].waitForExistence(timeout: 10))
        focus(quickConnect, in: app)
        remote.press(.select)
        XCTAssertTrue(code.waitForExistence(timeout: 20))

        // The driving script approves this code as the test user. Skips approval if nothing does.
        print("QUICKCONNECT_CODE=\(code.label)")
        guard app.tabBars.firstMatch.waitForExistence(timeout: 60) else {
            throw XCTSkip("Nothing approved the Quick Connect code")
        }
        sleep(3)
        capture("quick-connect-signed-in")
        focus(app.tabBars.buttons["Home"], in: app)
        for _ in 0..<4 {
            remote.press(.right)
            usleep(500_000)
        }
        remote.press(.select)
        let signOut = app.buttons["signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 10))
        focus(signOut, in: app)
        remote.press(.select)
        XCTAssertTrue(app.buttons["otherUser"].waitForExistence(timeout: 20))
    }
}
