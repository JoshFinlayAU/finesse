import XCTest

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

    @MainActor
    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
