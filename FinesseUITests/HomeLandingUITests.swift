import XCTest

/// The billboard and its rows on the fake server, whose art is very bright or very dark on purpose.
@MainActor
final class HomeLandingUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication()

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    private var heroTitle: XCUIElement { app.descendants(matching: .any)["heroTitle"] }

    private func launch() {
        continueAfterFailure = false
        app.launchArguments = ["-FinesseFakeServer"]
        app.launch()
        XCTAssertTrue(app.buttons["heroPlay"].waitForExistence(timeout: 20))
        sleep(2)
        XCTAssertTrue(app.tabBars.buttons["Home"].hasFocus, "Focus should start on the tab bar")
    }

    private func press(_ button: XCUIRemote.Button) {
        remote.press(button)
        sleep(2)
    }

    private func expectFocus(on identifier: String, _ message: String, line: UInt = #line) {
        XCTAssertEqual(focused.identifier, identifier, message, line: line)
    }

    private func expectCard(_ label: String, line: UInt = #line) {
        XCTAssertEqual(focused.label, label, line: line)
        XCTAssertEqual(heroTitle.label, label, "The billboard should follow the card", line: line)
    }

    func testDownThroughTheRowsAndBackOutAgain() throws {
        launch()
        capture("landing-1-tab-bar")
        press(.down)
        expectFocus(on: "heroPlay", "Down from the tab bar should stop at Play")
        capture("landing-2-play")

        press(.down)
        expectCard("A Film in Progress")
        capture("landing-3-continue-watching")
        press(.down)
        expectCard("A Long Show")
        capture("landing-4-next-up-bright")
        press(.down)
        expectCard("New Film 8")
        capture("landing-5-recent-movies")
        press(.down)
        expectCard("A Long Show")
        capture("landing-6-recent-tv")

        press(.menu)
        expectFocus(on: "heroPlay", "Back from a row should return to Play")
        XCTAssertEqual(heroTitle.label, "A Film in Progress", "The billboard should return to the featured item")
        capture("landing-7-back-to-play")
        press(.menu)
        XCTAssertTrue(app.tabBars.buttons["Home"].hasFocus, "Back from Play should reach the tab bar")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testUpFromTheFirstRowReachesTheButtonsThenTheTabBar() throws {
        launch()
        press(.down)
        press(.down)
        expectCard("A Film in Progress")
        press(.up)
        expectFocus(on: "heroPlay", "Up from the first row should reach Play")
        press(.up)
        XCTAssertTrue(app.tabBars.buttons["Home"].hasFocus, "Up from Play should reach the tab bar")
    }

    func testAnUnwatchedEpisodeGivesNothingAway() throws {
        launch()
        press(.down)
        press(.down)
        press(.down)
        expectCard("A Long Show")
        let overview = app.descendants(matching: .any)["heroOverview"]
        XCTAssertEqual(overview.label, "What the whole show is about, and safe to read.")
        XCTAssertFalse(app.descendants(matching: .any)["heroSubtitle"].exists, "The episode's name stays hidden")
    }

    func testTheBillboardFollowsAcrossARowAndSweepingStaysResponsive() throws {
        launch()
        press(.down)
        press(.down)
        press(.down)
        press(.down)
        expectCard("New Film 8")
        press(.right)
        expectCard("New Film 7")
        capture("landing-8-next-card")

        // Quick presses land on the last card, and the billboard catches up with it.
        for _ in 0..<3 {
            remote.press(.right)
            usleep(150_000)
        }
        sleep(2)
        expectCard("New Film 4")
    }

    func testPositionIsKeptOnReturnFromDetailAndThePlayer() throws {
        launch()
        press(.down)
        press(.down)
        press(.down)
        press(.down)
        press(.right)
        expectCard("New Film 7")

        press(.select)
        XCTAssertTrue(app.buttons["detailPlay"].waitForExistence(timeout: 10))
        press(.menu)
        expectCard("New Film 7")
        capture("landing-9-back-from-detail")

        // The fake has no media, so the real player opens and shows its error.
        press(.playPause)
        XCTAssertTrue(app.staticTexts["Something Went Wrong"].waitForExistence(timeout: 10))
        press(.menu)
        sleep(1)
        expectCard("New Film 7")
    }

    func testTheButtonsActOnTheFeaturedItem() throws {
        launch()
        press(.down)
        expectFocus(on: "heroPlay", "Down from the tab bar should stop at Play")
        press(.right)
        expectFocus(on: "heroMoreInfo", "More Info is right of Play")
        press(.select)
        XCTAssertTrue(app.buttons["detailPlay"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["A Film in Progress"].exists, "More Info should open the featured item")
        press(.menu)
        expectFocus(on: "heroMoreInfo", "Back from Detail should return to More Info")
        press(.left)

        press(.select)
        XCTAssertTrue(app.staticTexts["Something Went Wrong"].waitForExistence(timeout: 10), "Play should open the player")
        press(.menu)
        sleep(1)
        expectFocus(on: "heroPlay", "Back from the player should return to Play")
    }

    func testTheBillboardRotatesOnlyWhenNothingIsBeingBrowsed() throws {
        launch()
        press(.down)
        let first = heroTitle.label
        let changed = expectation(for: NSPredicate(format: "label != %@", first), evaluatedWith: heroTitle)
        wait(for: [changed], timeout: 30)
        expectFocus(on: "heroPlay", "Rotating should leave focus where it was")
        capture("landing-10-rotated")

        press(.down)
        let onCard = heroTitle.label
        XCTAssertEqual(focused.label, onCard)
        sleep(20)
        XCTAssertEqual(heroTitle.label, onCard, "The billboard should stay on the focused card")
    }
}

/// The billboard on the test server's real art and real library size. Skips without credentials.
@MainActor
final class HomeRealLibraryUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication.forSignIn()

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    private func launchToHome(extraEnvironment: [String: String] = [:]) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let server = environment["JELLYFIN_URL"], let username = environment["JELLYFIN_USERNAME"] else {
            throw XCTSkip("Test server variables are not set")
        }
        continueAfterFailure = false
        app.launchEnvironment.merge(extraEnvironment) { $1 }
        app.launch()
        let address = app.textFields["serverAddress"]
        if address.waitForExistence(timeout: 8) {
            enter(server, into: address, in: app)
            focus(app.buttons["connect"], in: app)
            remote.press(.select)
            let other = app.buttons["otherUser"]
            XCTAssertTrue(other.waitForExistence(timeout: 20))
            focus(other, in: app)
            remote.press(.select)
            let name = app.textFields["username"]
            XCTAssertTrue(name.waitForExistence(timeout: 10))
            enter(username, into: name, in: app)
            enter(TypedPassword.first, into: app.secureTextFields["password"], in: app)
            focus(app.buttons["signIn"], in: app)
            remote.press(.select)
        }
        XCTAssertTrue(app.buttons["heroMoreInfo"].waitForExistence(timeout: 30))
    }

    /// Walks down the rows and along one, capturing real art, and proves the details follow it.
    func testTheBillboardOverRealArt() throws {
        try launchToHome()
        sleep(4)
        capture("real-1-landing")
        let title = app.descendants(matching: .any)["heroTitle"]
        XCTAssertFalse(title.label.isEmpty)
        let overview = app.descendants(matching: .any)["heroOverview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10), "A real item should have an overview")

        focusFirstHomeCard(in: app)
        var seen = Set<String>()
        for row in 0..<5 {
            sleep(2)
            capture("real-2-row-\(row)")
            seen.insert(title.label)
            for column in 0..<3 {
                remote.press(.right)
                sleep(2)
                capture("real-3-row-\(row)-card-\(column)")
                seen.insert(title.label)
            }
            remote.press(.down)
        }
        XCTAssertGreaterThan(seen.count, 4, "The billboard should change as focus moves")
    }

    /// The server has over a thousand films and hundreds of shows, and Home asks for 24 of each per
    /// row, so loading every row's art would be hundreds of requests.
    func testOpeningHomeOnlyLoadsTheArtInView() throws {
        let log = NSTemporaryDirectory() + "finesse-images-\(UUID().uuidString).log"
        XCTAssertTrue(FileManager.default.createFile(atPath: log, contents: nil))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: log) }
        try launchToHome(extraEnvironment: ["FINESSE_IMAGE_REQUEST_LOG": log])
        sleep(10)
        let lines = try String(contentsOfFile: log, encoding: .utf8).split(separator: "\n").count
        print("HOME image requests after opening: \(lines)")
        XCTAssertGreaterThan(lines, 0, "The count should see real requests, or this test proves nothing")
        XCTAssertLessThan(lines, 60, "Opening Home should not load the art of rows it isn't showing")
    }

    /// Holding a course along a full row and down the rows has to keep up with the remote.
    func testScrollingKeepsUpOnARealLibrary() throws {
        try launchToHome()
        sleep(4)
        focusFirstHomeCard(in: app)
        // Recently Added Movies always has a full row, and the rows above it might not.
        let movies = app.staticTexts["Recently Added Movies"]
        // A focused row's title settles under the details, so its position shows when it's reached.
        for _ in 0..<5 where !(movies.exists && movies.frame.minY < 600) {
            remote.press(.down)
            sleep(2)
        }
        XCTAssertTrue(movies.exists && movies.frame.minY < 600, "Should have reached Recently Added Movies")
        let start = Date()
        var labels = Set<String>()
        for _ in 0..<20 {
            remote.press(.right)
            usleep(300_000)
            // Nothing reports focus in the moment it's moving between cards.
            if focused.exists { labels.insert(focused.label) }
        }
        let along = Date().timeIntervalSince(start)
        let down = Date()
        for _ in 0..<6 {
            remote.press(.down)
            usleep(500_000)
            if focused.exists { labels.insert(focused.label) }
        }
        let across = Date().timeIntervalSince(down)
        print("HOME scrolling: 20 cards in \(along)s, 6 rows in \(across)s, \(labels.count) distinct cards")
        XCTAssertGreaterThan(labels.count, 15, "Focus should have moved along a full row and down the rows")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
