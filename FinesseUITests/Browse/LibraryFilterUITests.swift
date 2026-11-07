import XCTest

/// Moves around the filter panel as a person would. Rows depend on what the server offers, so this
/// goes by what has focus rather than counting presses.
@MainActor
struct FilterPanelDriver {
    let app: XCUIApplication
    private var remote: XCUIRemote { .shared }

    var summary: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "panelSummary").firstMatch
    }

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    private func press(_ button: XCUIRemote.Button) {
        remote.press(button)
        usleep(400_000)
    }

    /// From a button in the library's top row, with focus already on it.
    func open() {
        remote.press(.select)
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "The filter panel should open")
        // Choices are counted as the panel opens, so rows appear after it does.
        sleep(4)
    }

    func hasFocus(_ title: String) -> Bool {
        guard focused.exists else { return false }
        if focused.label == title || focused.label.hasPrefix("\(title),") { return true }
        let inside = focused.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, "\(title),"))
        return inside.count > 0
    }

    /// Down through the list, then back up in case the row was above where focus started.
    func focusRow(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        var last = ""
        for direction in [XCUIRemote.Button.down, .up] {
            for _ in 0..<45 {
                if hasFocus(title) { return }
                press(direction)
                let now = focused.exists ? focused.label : ""
                if now == last { break }
                last = now
            }
        }
        XCTAssertTrue(hasFocus(title), "\(title) should be reachable, focus is on \(last)", file: file, line: line)
    }

    /// An open Menu's rows report focus only from inside, with no label to tell if focus has stopped moving.
    func chooseInMenu(_ title: String, moving direction: XCUIRemote.Button, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<20 where !hasFocus(title) {
            press(direction)
        }
        XCTAssertTrue(hasFocus(title), "\(title) should be in the menu", file: file, line: line)
        remote.press(.select)
        sleep(2)
    }

    func choose(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        focusRow(title, file: file, line: line)
        remote.press(.select)
        sleep(2)
    }

    /// One press right of any row, then back to the list.
    func clearFilters(file: StaticString = #filePath, line: UInt = #line) {
        press(.right)
        XCTAssertTrue(app.buttons["panelClearFilters"].hasFocus, "Clear Filters should be right of the list", file: file, line: line)
        remote.press(.select)
        sleep(3)
        // Clear goes away, so focus has to come back to the list by itself.
        XCTAssertTrue(focused.exists, "Something should keep focus", file: file, line: line)
    }

    /// Back up one page, or out of the panel from its first page.
    func back() {
        remote.press(.menu)
        sleep(1)
    }

    func close() {
        back()
        XCTAssertTrue(summary.waitForNonExistence(timeout: 5), "Back from the first page should close the panel")
        sleep(2)
    }

    func exists(_ title: String) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, "\(title),")).firstMatch.exists
    }
}

/// The filter panel in the real app against the test server, with a screenshot of each level.
/// Skips without credentials. Changes only the test user's own state and undoes it.
@MainActor
final class LibraryFilterUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication.forSignIn()
    private lazy var panel = FilterPanelDriver(app: app)

    private func environment(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name] else {
            throw XCTSkip("\(name) is not set")
        }
        return value
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            usleep(500_000)
        }
    }

    private var filter: XCUIElement { app.buttons["libraryFilter"] }
    private var clear: XCUIElement { app.buttons["libraryClearFilters"] }
    private var count: XCUIElement { app.staticTexts["libraryCount"] }

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

    private func openTab(_ name: String) {
        let index = ["Home", "Movies", "TV Shows", "Search", "Settings"].firstIndex(of: name) ?? 0
        press(.up, times: 4)
        press(.left, times: 5)
        press(.right, times: index)
        remote.press(.select)
        XCTAssertTrue(filter.waitForExistence(timeout: 20))
        sleep(4)
    }

    /// The top row doesn't exist at all once it has scrolled far enough off the screen.
    private var filterHasFocus: Bool {
        filter.exists && filter.hasFocus
    }

    /// Up from the grid lands on Sort. Filter is one to the right, and Clear is right of that.
    private func focusFilterButton() {
        // Where focus starts depends on how soon the grid arrived, and a remembered Random takes longer.
        press(.down)
        for _ in 0..<6 where !filterHasFocus {
            press(.up)
            if !filterHasFocus {
                press(.right)
            }
        }
        XCTAssertTrue(filterHasFocus, "Filter should be in the top row")
    }

    /// Remembered filters from an earlier failed run would change everything after this.
    private func clearAnyRememberedFilter() {
        focusFilterButton()
        if clear.exists {
            press(.right)
            remote.press(.select)
            sleep(3)
            if !filterHasFocus {
                press(.left)
            }
        }
        XCTAssertEqual(filter.value as? String, "All")
        XCTAssertTrue(filterHasFocus)
    }

    private func total(_ text: XCUIElement) -> Int {
        let digits = text.label.prefix { $0.isNumber || $0 == "," }.filter(\.isNumber)
        return Int(digits) ?? -1
    }

    func testPanelLevelsLongListsCountsBackAndRememberingOnMovies() throws {
        try launchSignedIn()
        openTab("Movies")
        clearAnyRememberedFilter()
        let everything = total(count)
        XCTAssertGreaterThan(everything, 0)
        capture("filter-1-library")

        panel.open()
        capture("filter-2-panel")
        // The test server has these, and has no 3D or trailers, so those must not be offered.
        XCTAssertFalse(panel.exists("3D"), "Nothing here is 3D")
        XCTAssertFalse(panel.exists("Trailer"), "Nothing here has a trailer")
        XCTAssertFalse(panel.exists("Continuing"), "Series status isn't for movies")

        // Rows stay open after a choice, and the count changes behind them.
        panel.choose("4K")
        capture("filter-3-4k-chosen")
        XCTAssertEqual(filter.value as? String, "Filtered")
        let fourK = total(panel.summary)
        XCTAssertGreaterThan(fourK, 0)
        XCTAssertLessThan(fourK, everything)
        panel.choose("HD")
        let fourKOrHD = total(panel.summary)
        XCTAssertGreaterThan(fourKOrHD, fourK, "The server treats 4K and HD as either one")
        panel.choose("HD")
        XCTAssertEqual(total(panel.summary), fourK)
        panel.choose("4K")

        // A short list.
        panel.choose("Genres")
        capture("filter-4-genres")
        press(.down)
        remote.press(.select)
        sleep(2)
        capture("filter-5-genre-chosen")
        panel.back()
        XCTAssertTrue(panel.summary.waitForExistence(timeout: 5), "Back should return to the first page")
        capture("filter-6-back-with-selection")

        // A very long list opens by letter.
        panel.choose("Tags")
        capture("filter-7-tags-letters")
        // A searchable list starts on its keyboard. Below that, Clear is one press right.
        press(.down)
        press(.right)
        XCTAssertTrue(app.buttons["panelClearFilters"].hasFocus, "Clear Filters should be right of the list")
        press(.left)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "letterRow-A").firstMatch.waitForExistence(timeout: 5))
        panel.choose("A")
        capture("filter-8-tags-one-letter")
        press(.down)
        remote.press(.select)
        sleep(2)
        capture("filter-9-tag-chosen")
        panel.back()
        capture("filter-10-tags-with-selected")
        panel.back()
        XCTAssertTrue(panel.summary.waitForExistence(timeout: 5))

        // Studios load when opened, and letters come from the server.
        panel.choose("Studios")
        sleep(3)
        capture("filter-11-studios")
        panel.back()
        panel.choose("Starts With")
        sleep(5)
        capture("filter-12-letters")
        panel.back()
        panel.choose("Community Rating")
        capture("filter-13-rating")
        panel.back()
        panel.choose("Audio Languages")
        capture("filter-14-audio")
        panel.back()

        // Back at each level has been shown, and this closes the panel with focus where it was.
        panel.close()
        XCTAssertTrue(filter.hasFocus, "Focus should return to Filter")
        capture("filter-15-filtered-grid")
        XCTAssertEqual(filter.value as? String, "Filtered")
        XCTAssertLessThan(total(count), everything)
        XCTAssertTrue(filter.label.contains("(2)"), "It should say two are on, got \(filter.label)")
        XCTAssertTrue(clear.exists, "Clear Filters should be next to Filter")

        // Filters are remembered across a relaunch, then Clear is one press away.
        let filtered = total(count)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        sleep(2)
        openTab("Movies")
        capture("filter-16-remembered")
        XCTAssertEqual(filter.value as? String, "Filtered", "The filter should be remembered")
        XCTAssertEqual(total(count), filtered)

        focusFilterButton()
        press(.right)
        XCTAssertTrue(clear.hasFocus, "Clear should be right of Filter")
        remote.press(.select)
        sleep(4)
        XCTAssertEqual(filter.value as? String, "All")
        XCTAssertEqual(total(count), everything)
        XCTAssertFalse(clear.exists)
        XCTAssertTrue(filter.hasFocus, "Focus should stay in the top row after Clear goes away")
        capture("filter-17-cleared")
    }

    /// Search inside a long list, with the keyboard the system gives a searchable list.
    func testLongListSearch() throws {
        try launchSignedIn()
        openTab("Movies")
        clearAnyRememberedFilter()
        panel.open()
        panel.choose("Tags")
        press(.up, times: 2)
        capture("filter-20-tags-search-focus")
        app.typeText("war")
        sleep(3)
        capture("filter-21-tags-search-typed")
        press(.down)
        sleep(1)
        capture("filter-22-tags-search-results")
        remote.press(.menu)
        sleep(1)
        panel.back()
        panel.back()
        if panel.summary.exists {
            panel.close()
        }
        XCTAssertEqual(filter.value as? String, "All", "Only typing, nothing should be chosen")
    }

    /// Random keeps one order through Detail and Back, and reaches past the first page.
    func testRandomKeepsItsOrderThroughDetailAndBack() throws {
        try launchSignedIn()
        openTab("Movies")
        clearAnyRememberedFilter()
        let sort = app.buttons["librarySort"]
        // A Menu doesn't report focus to XCUITest, so opening it is what proves it had focus.
        press(.left)
        remote.press(.select)
        sleep(2)
        panel.chooseInMenu("Random", moving: .down)
        sleep(3)
        XCTAssertEqual(sort.value as? String, "Random")
        capture("filter-40-random")

        // Well past the first page of 60, six to a row.
        press(.down, times: 14)
        sleep(3)
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.label
        XCTAssertFalse(card.isEmpty)
        remote.press(.select)
        XCTAssertTrue(app.buttons["detailWatched"].waitForExistence(timeout: 20))
        sleep(2)
        remote.press(.menu)
        sleep(3)
        let back = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.label
        XCTAssertEqual(back, card, "Back should land on the same card in the same order")
        capture("filter-41-random-back")

        // Up to the top row, then ask for a new order and put Name back.
        // The card is in the rightmost column, so going up leads to Filter, which does report focus.
        // Filter doesn't exist at all until it has scrolled back near the screen.
        for _ in 0..<30 where !filterHasFocus {
            press(.up)
        }
        XCTAssertTrue(filterHasFocus, "Up from the grid should reach the top row")
        press(.left)
        remote.press(.select)
        sleep(2)
        capture("filter-42-random-menu")
        let shuffle = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Shuffle Again")).firstMatch
        let name = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Name")).firstMatch
        XCTAssertTrue(shuffle.exists && name.exists)
        XCTAssertLessThan(shuffle.frame.minY, name.frame.minY, "Shuffle Again should be above the sort rows")
        // From where the menu opens, it should only be a press or two away.
        for _ in 0..<2 where !panel.hasFocus("Shuffle Again") {
            press(.up)
        }
        XCTAssertTrue(panel.hasFocus("Shuffle Again"), "Shuffle Again should be within two presses of where the menu opens")
        remote.press(.select)
        sleep(2)
        sleep(3)
        XCTAssertEqual(sort.value as? String, "Random")
        remote.press(.select)
        sleep(2)
        panel.chooseInMenu("Name", moving: .up)
        sleep(3)
        XCTAssertEqual(sort.value as? String, "Name")
    }

    /// TV Shows has its own sorts and filters.
    func testTVShowsOfferTheirOwnOptions() throws {
        try launchSignedIn()
        openTab("TV Shows")
        clearAnyRememberedFilter()
        let everything = total(count)

        panel.open()
        capture("filter-30-tv-panel")
        panel.focusRow("Continuing")
        XCTAssertTrue(panel.exists("Ended"))
        panel.choose("Continuing")
        let continuing = total(panel.summary)
        XCTAssertGreaterThan(continuing, 0)
        XCTAssertLessThan(continuing, everything)
        panel.choose("Ended")
        let either = total(panel.summary)
        XCTAssertGreaterThan(either, continuing, "Statuses match any of them")
        capture("filter-31-tv-status")
        panel.choose("Ended")
        panel.choose("Continuing")
        panel.close()
        XCTAssertEqual(filter.value as? String, "All")

        // Left of Filter is Sort, which has its own list here.
        press(.left)
        remote.press(.select)
        sleep(2)
        capture("filter-32-tv-sort-menu")
        let row = { (title: String) in
            self.app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
        }
        XCTAssertTrue(row("Date Episode Added").waitForExistence(timeout: 5))
        XCTAssertFalse(row("Critic Rating").exists, "Series have no critic ratings")
        XCTAssertFalse(row("Video Bitrate").exists, "It does nothing on series")
        remote.press(.menu)
    }
}

extension TestServerAPI {
    func setFavorite(_ favorite: Bool, _ movie: Movie) async throws {
        _ = try await Self.send(favorite ? "POST" : "DELETE", "\(server)/UserFavoriteItems/\(movie.id)", token: token, body: nil)
    }
}
