import XCTest

/// Drives the real app with the Siri Remote API against the test server, and keeps a screenshot
/// of each screen. Skips without credentials. Reset the simulator keychain first, so it starts signed out.
@MainActor
final class SignInFlowUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication()

    private func environment(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name] else {
            throw XCTSkip("\(name) is not set")
        }
        return value
    }

    func testSignInHomeBackPathAndSignOut() throws {
        let server = try environment("JELLYFIN_URL")
        let username = try environment("JELLYFIN_USERNAME")
        let password = try environment("JELLYFIN_PASSWORD")
        continueAfterFailure = false
        app.launch()

        // Server address.
        let address = app.textFields["serverAddress"]
        XCTAssertTrue(address.waitForExistence(timeout: 20))
        capture("1-server-entry")
        enter(server, into: address)
        focus(app.buttons["connect"])
        remote.press(.select)

        // User picker. The hidden test user isn't listed, so use Other User.
        let other = app.buttons["otherUser"]
        XCTAssertTrue(other.waitForExistence(timeout: 20))
        capture("2-user-picker")

        // Back from the picker returns to the server step, with the address kept.
        remote.press(.menu)
        XCTAssertTrue(app.buttons["connect"].waitForExistence(timeout: 10))
        focus(app.buttons["connect"])
        remote.press(.select)
        XCTAssertTrue(other.waitForExistence(timeout: 20))

        focus(other)
        remote.press(.select)
        let usernameField = app.textFields["username"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 10))
        enter(username, into: usernameField)
        let passwordField = app.secureTextFields["password"]
        enter("definitely-wrong", into: passwordField)
        focus(app.buttons["signIn"])
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Incorrect username or password."].waitForExistence(timeout: 20))
        capture("3-wrong-password")

        enter(password, into: passwordField)
        focus(app.buttons["signIn"])
        remote.press(.select)

        // Home.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30))
        let recentlyAdded = app.staticTexts["Recently Added"]
        XCTAssertTrue(recentlyAdded.waitForExistence(timeout: 30))
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
        XCTAssertTrue(recentlyAdded.waitForExistence(timeout: 10))
        capture("7-back-on-home")

        // Relaunch restores the session with no sign-in.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Recently Added"].waitForExistence(timeout: 30))

        // Settings, then sign out.
        remote.press(.menu)
        sleep(1)
        for _ in 0..<4 {
            remote.press(.right)
            usleep(500_000)
        }
        remote.press(.select)
        let signOut = app.buttons["signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 10))
        sleep(1)
        capture("8-settings")
        focus(signOut)
        remote.press(.select)
        XCTAssertTrue(app.buttons["otherUser"].waitForExistence(timeout: 20))
        capture("9-after-sign-out")
    }

    func testQuickConnectShowsCodeAndBackLeaves() throws {
        let server = try environment("JELLYFIN_URL")
        continueAfterFailure = false
        app.launch()
        let address = app.textFields["serverAddress"]
        XCTAssertTrue(address.waitForExistence(timeout: 20))
        enter(server, into: address)
        focus(app.buttons["connect"])
        remote.press(.select)
        let quickConnect = app.buttons["quickConnect"]
        XCTAssertTrue(quickConnect.waitForExistence(timeout: 20))
        focus(quickConnect)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["quickConnectCode"].waitForExistence(timeout: 20))
        capture("quick-connect")
        remote.press(.menu)
        XCTAssertTrue(app.buttons["otherUser"].waitForExistence(timeout: 10))
    }

    /// Moves focus to an element by trying each direction, as a person would with the remote.
    private func focus(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        for direction in [XCUIRemote.Button.down, .down, .down, .up, .up, .up, .up, .up, .up, .down, .down] {
            if element.hasFocus { return }
            remote.press(direction)
            usleep(400_000)
        }
        XCTAssertTrue(element.hasFocus, "Could not focus \(element)")
    }

    private func enter(_ text: String, into field: XCUIElement) {
        focus(field)
        remote.press(.select)
        sleep(1)
        clearKeyboardField()
        app.typeText(text)
        sleep(1)
        // Leave the full-screen keyboard.
        remote.press(.menu)
        sleep(1)
    }

    private func clearKeyboardField() {
        let delete = String(XCUIKeyboardKey.delete.rawValue)
        let current = app.keyboards.firstMatch.exists ? app.textFields.firstMatch.value as? String : nil
        if let current, !current.isEmpty, current != app.textFields.firstMatch.placeholderValue {
            app.typeText(String(repeating: delete, count: current.count))
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
