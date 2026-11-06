import XCTest

/// What the tests type instead of a password, because XCTest records typed text in result bundles
/// and the simulator log. The app swaps these for the real values, in Debug builds only.
enum TypedPassword {
    static let first = "ui-test-password-1"
    static let second = "ui-test-password-2"
}

extension XCUIApplication {
    /// An app that can resolve `TypedPassword` values, read from the test's own environment.
    @MainActor
    static func forSignIn() -> XCUIApplication {
        let app = XCUIApplication()
        let environment = ProcessInfo.processInfo.environment
        app.launchEnvironment["FINESSE_UI_TEST_PASSWORD_1"] = environment["JELLYFIN_PASSWORD"]
        app.launchEnvironment["FINESSE_UI_TEST_PASSWORD_2"] = environment["JELLYFIN_PASSWORD_2"]
        return app
    }
}

extension XCTestCase {
    /// Moves focus to an element by trying each direction, as a person would with the remote.
    /// List rows report focus on an inner element, so this also compares the focused element's label.
    @MainActor
    func focus(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let moves = Array(repeating: XCUIRemote.Button.up, count: 4) + Array(repeating: XCUIRemote.Button.down, count: 16)
        for move in moves {
            if isFocused(element, in: app) { return }
            XCUIRemote.shared.press(move)
            usleep(400_000)
        }
        XCTAssertTrue(isFocused(element, in: app), "Could not focus \(element)")
    }

    @MainActor
    private func isFocused(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.hasFocus { return true }
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return focused.exists && !element.label.isEmpty && focused.label == element.label
    }

    /// Types into a field through the full-screen keyboard, replacing what it held.
    @MainActor
    func enter(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        focus(field, in: app)
        XCUIRemote.shared.press(.select)
        sleep(1)
        let keyboardField = app.textFields.firstMatch
        if app.keyboards.firstMatch.exists, let current = keyboardField.value as? String,
           !current.isEmpty, current != keyboardField.placeholderValue {
            app.typeText(String(repeating: String(XCUIKeyboardKey.delete.rawValue), count: current.count))
        }
        app.typeText(text)
        sleep(1)
        // Leave the full-screen keyboard.
        XCUIRemote.shared.press(.menu)
        sleep(1)
    }

    @MainActor
    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
