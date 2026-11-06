import XCTest

/// Drives Library, Search and Detail in the real app against the test server, with a screenshot of
/// each screen. Skips without credentials. Changes only the test user's own state and undoes it.
@MainActor
final class BrowseFlowUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication.forSignIn()

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

    /// A row of an open Menu, found by its text.
    private func menuItem(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private var focusedLabel: String {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.label
    }

    /// Reuses a stored session when there is one. Takes no screenshot of the user picker.
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
            enter(server, into: address)
            focus(app.buttons["connect"], in: app)
            remote.press(.select)
        }
        XCTAssertTrue(other.waitForExistence(timeout: 20))
        focus(other, in: app)
        remote.press(.select)
        let usernameField = app.textFields["username"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 10))
        enter(username, into: usernameField)
        enter(TypedPassword.first, into: app.secureTextFields["password"])
        focus(app.buttons["signIn"], in: app)
        remote.press(.select)
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30))
    }

    private func enter(_ text: String, into field: XCUIElement) {
        focus(field, in: app)
        remote.press(.select)
        sleep(1)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40) + text)
        sleep(1)
        // Leave the full-screen keyboard.
        remote.press(.menu)
        sleep(1)
    }

    /// Moves as a person would: up to the tab bar, back to Home, then across.
    private func openTab(_ name: String) {
        let index = ["Home", "Movies", "TV Shows", "Search", "Settings"].firstIndex(of: name) ?? 0
        press(.up, times: 4)
        press(.left, times: 5)
        press(.right, times: index)
        remote.press(.select)
        sleep(2)
    }

    func testLibraryGridSortFilterPagingAndBack() throws {
        try launchSignedIn()
        openTab("Movies")
        let sort = app.buttons["librarySort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 20))
        sleep(4)
        capture("library-1-movies")

        // Sort menu, reached from the grid with one press up, choosing Date Added. A Menu doesn't
        // report focus to XCUITest, so opening it is what proves it had focus.
        press(.up)
        sleep(1)
        capture("library-1b-up-from-grid")
        remote.press(.select)
        sleep(2)
        capture("library-2-sort-menu")
        XCTAssertTrue(menuItem("Date Added").waitForExistence(timeout: 5), "Up from the first poster should reach Sort")
        // Rows don't report focus either. The checked row takes focus, and Date Added is the next one.
        press(.down)
        remote.press(.select)
        sleep(4)
        capture("library-3-sorted-date-added")
        XCTAssertEqual(sort.value as? String, "Date Added")

        // Filter menu, one press right of Sort, choosing Unwatched, then clearing it.
        let filter = app.buttons["libraryFilter"]
        press(.right)
        remote.press(.select)
        sleep(2)
        capture("library-4-filter-menu")
        XCTAssertTrue(menuItem("Unwatched").waitForExistence(timeout: 5), "Right of Sort should be Filter")
        press(.down)
        remote.press(.select)
        sleep(4)
        capture("library-5-filtered")
        XCTAssertEqual(filter.value as? String, "Filtered")
        remote.press(.select)
        sleep(1)
        // From the checked Unwatched row: Watched, Favourites, Genre, Year, Rating, Clear Filters.
        XCTAssertTrue(menuItem("Clear Filters").waitForExistence(timeout: 5))
        press(.down, times: 6)
        remote.press(.select)
        sleep(3)
        capture("library-5b-filter-cleared")
        XCTAssertEqual(filter.value as? String, "All")

        // Well past the first page of 60, six to a row.
        press(.down, times: 14)
        sleep(3)
        capture("library-6-past-first-page")
        let deepCard = focusedLabel
        XCTAssertFalse(deepCard.isEmpty)
        XCTAssertNotEqual(deepCard, "librarySort")

        // Detail and Back returns to the same card.
        remote.press(.select)
        XCTAssertTrue(app.buttons["detailWatched"].waitForExistence(timeout: 20))
        sleep(3)
        capture("detail-1-movie")
        remote.press(.menu)
        sleep(2)
        capture("library-7-back-same-position")
        XCTAssertEqual(focusedLabel, deepCard)

        // Menu from the grid goes up to the tab bar rather than leaving the app.
        remote.press(.menu)
        sleep(2)
        capture("library-8-menu-to-tabs")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testMovieDetailActionsRowsAndPlayer() throws {
        try launchSignedIn()
        openTab("Movies")
        XCTAssertTrue(app.buttons["librarySort"].waitForExistence(timeout: 20))
        sleep(3)
        remote.press(.select)

        let watched = app.buttons["detailWatched"]
        XCTAssertTrue(watched.waitForExistence(timeout: 20))
        sleep(3)
        let play = app.buttons["detailPlay"]
        XCTAssertTrue(play.exists)
        XCTAssertTrue(play.hasFocus, "Play should take focus when the page opens")

        // Favourite on and off, watched on and off.
        let favourite = app.buttons["detailFavourite"]
        press(.right, times: 2)
        XCTAssertTrue(favourite.hasFocus)
        remote.press(.select)
        sleep(2)
        capture("detail-2-favourited")
        remote.press(.select)
        sleep(2)
        press(.left)
        XCTAssertTrue(watched.hasFocus)
        remote.press(.select)
        sleep(2)
        capture("detail-3-watched")
        remote.press(.select)
        sleep(2)

        // Rows under the header.
        press(.down)
        sleep(2)
        capture("detail-4-movie-cast")
        press(.down)
        sleep(2)
        capture("detail-5-movie-related")

        // Play goes to the player, and Back returns here.
        press(.up, times: 3)
        press(.left, times: 3)
        XCTAssertTrue(play.hasFocus)
        remote.press(.select)
        sleep(6)
        capture("detail-6-player")
        remote.press(.menu)
        sleep(1)
        if !watched.exists {
            remote.press(.menu)
        }
        XCTAssertTrue(watched.waitForExistence(timeout: 20))
        capture("detail-7-back-from-player")
    }

    func testShowSeasonEpisodeHierarchyAndBack() throws {
        try launchSignedIn()
        openTab("TV Shows")
        XCTAssertTrue(app.buttons["librarySort"].waitForExistence(timeout: 20))
        sleep(4)
        capture("library-9-shows")
        // Selecting the tab leaves focus on the first poster.
        let show = focusedLabel
        remote.press(.select)

        let watched = app.buttons["detailWatched"]
        XCTAssertTrue(watched.waitForExistence(timeout: 20))
        sleep(3)
        capture("detail-8-show")
        XCTAssertTrue(app.staticTexts["Seasons"].exists)

        press(.down)
        sleep(2)
        capture("detail-9-show-seasons-row")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Episodes"].waitForExistence(timeout: 20))
        sleep(3)
        capture("detail-10-season")

        press(.down)
        sleep(2)
        capture("detail-11-season-episodes")
        remote.press(.select)
        XCTAssertTrue(app.buttons["detailGoToShow"].waitForExistence(timeout: 20))
        sleep(3)
        capture("detail-12-episode")
        press(.down)
        sleep(2)
        capture("detail-13-episode-more")

        // Back through episode, season and show to the grid.
        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["Episodes"].waitForExistence(timeout: 10))
        sleep(1)
        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["Seasons"].waitForExistence(timeout: 10))
        sleep(1)
        remote.press(.menu)
        XCTAssertTrue(app.buttons["librarySort"].waitForExistence(timeout: 10))
        sleep(1)
        capture("library-10-back-at-shows")
        XCTAssertEqual(focusedLabel, show)
    }

    func testSearchResultsAndBack() throws {
        try launchSignedIn()

        // A word from a real title, so this works whatever is in the library.
        openTab("Movies")
        XCTAssertTrue(app.buttons["librarySort"].waitForExistence(timeout: 20))
        sleep(3)
        let title = focusedLabel
        let term = title.split(separator: " ").map(String.init).max { $0.count < $1.count } ?? title
        XCTAssertFalse(term.isEmpty)

        openTab("Search")
        sleep(1)
        capture("search-1-empty")
        press(.down)
        app.typeText(term)
        sleep(4)
        capture("search-2-typed")
        XCTAssertTrue(app.staticTexts["Movies"].waitForExistence(timeout: 20))
        press(.down, times: 5)
        sleep(2)
        capture("search-3-results")
        let result = focusedLabel
        remote.press(.select)
        XCTAssertTrue(app.buttons["detailWatched"].waitForExistence(timeout: 20))
        sleep(2)
        capture("search-4-detail")
        remote.press(.menu)
        sleep(2)
        capture("search-5-back")
        XCTAssertEqual(focusedLabel, result)
    }
}
