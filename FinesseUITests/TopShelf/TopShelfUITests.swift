import XCTest

/// The real shelf on the simulator's Home Screen, drawn by the system from our extension, against
/// the test server. Skips without credentials. Changes only the test user's own state and undoes it.
@MainActor
final class TopShelfUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication.forSignIn()
    private let home = XCUIApplication(bundleIdentifier: "com.apple.PineBoard")

    private func environment(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name] else {
            throw XCTSkip("\(name) is not set")
        }
        return value
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            usleep(600_000)
        }
    }

    private func launchSignedIn() throws {
        let server = try environment("JELLYFIN_URL")
        let username = try environment("JELLYFIN_USERNAME")
        _ = try environment("JELLYFIN_PASSWORD")
        continueAfterFailure = false
        app.launch()

        let tabBar = app.tabBars.firstMatch
        let address = app.textFields["serverAddress"]
        let other = app.buttons["otherUser"]
        let deadline = Date.now.addingTimeInterval(30)
        while !tabBar.exists, !address.exists, !other.exists, Date.now < deadline {
            usleep(500_000)
        }
        if tabBar.exists { return }
        if address.exists {
            enter(server, into: address, in: app)
            focus(app.buttons["connect"], in: app)
            remote.press(.select)
        }
        XCTAssertTrue(other.waitForExistence(timeout: 20))
        focus(other, in: app)
        remote.press(.select)
        let usernameField = app.textFields["username"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 10))
        enter(username, into: usernameField, in: app)
        enter(TypedPassword.first, into: app.secureTextFields["password"], in: app)
        focus(app.buttons["signIn"], in: app)
        remote.press(.select)
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30))
    }

    private var focusedOnHome: XCUIElement {
        home.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// The Home Screen's icons are a grid, and where a new app lands depends on what else is there.
    private func focusFinesseIcon() {
        for move in [XCUIRemote.Button.down, .down, .down] + Array(repeating: .right, count: 6) + [.down] + Array(repeating: .left, count: 6) + [.up, .up, .up, .up] {
            if focusedOnHome.exists, focusedOnHome.label.contains("Finesse") { return }
            press(move)
        }
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(string: home.debugDescription)
        attachment.name = "home-\(name).txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Asked for by name, because it drives the simulator's Home Screen rather than the app.
    func testTheShelfShowsAndItsItemsOpenTheApp() throws {
        _ = try environment("FINESSE_TOP_SHELF_TEST")
        try launchSignedIn()
        sleep(3)
        remote.press(.home)
        sleep(4)
        capture("shelf-1-home")
        attach("start")
        focusFinesseIcon()
        print("HOME FOCUS: \(focusedOnHome.exists ? focusedOnHome.label : "nothing")")
        sleep(8)
        capture("shelf-2-finesse-focused")
        attach("focused")
        XCTAssertTrue(focusedOnHome.exists && focusedOnHome.label.contains("Finesse"), "Finesse should be reachable on the Home Screen")

        // Up from the icon goes into the shelf.
        press(.up)
        sleep(2)
        capture("shelf-3-in-the-shelf")
        attach("shelf")
        print("SHELF FOCUS: \(focusedOnHome.exists ? focusedOnHome.label : "nothing")")

        remote.press(.select)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "Choosing an item should open Finesse")
        sleep(6)
        capture("shelf-4-opened-detail")
        XCTAssertTrue(app.buttons["detailWatched"].waitForExistence(timeout: 20), "A press on a shelf item should open its Detail")

        // Play goes to the player.
        remote.press(.home)
        sleep(4)
        focusFinesseIcon()
        sleep(3)
        press(.up)
        sleep(1)
        remote.press(.playPause)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        sleep(6)
        capture("shelf-5-opened-player")
        XCTAssertTrue(
            app.descendants(matching: .any)["transportBar"].waitForExistence(timeout: 30),
            "Play on a shelf item should open the player"
        )
    }
}
