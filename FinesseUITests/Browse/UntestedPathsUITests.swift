import XCTest

/// Paths no other flow reaches: Resume and Start Over, Go to Show, Play on a show and a season,
/// the other filters, the empty and error states, and Back from every tab down to the Home screen.
/// Changes only the test user's own state and undoes it.
@MainActor
final class UntestedPathsUITests: XCTestCase {
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

    private func menuItem(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func moveInMenu(to title: String) {
        XCTAssertTrue(menuItem(title).waitForExistence(timeout: 5), "\(title) should be in the menu")
        for _ in 0..<12 where !menuRowHasFocus(title) {
            press(.down)
        }
        XCTAssertTrue(menuRowHasFocus(title), "\(title) should have focus")
    }

    private func menuRowHasFocus(_ title: String) -> Bool {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let inside = focused.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title))
        return focused.label == title || inside.count > 0
    }

    private func enter(_ text: String, into field: XCUIElement) {
        focus(field, in: app)
        remote.press(.select)
        sleep(1)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40) + text)
        sleep(1)
        remote.press(.menu)
        sleep(1)
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

    private func openTab(_ name: String) {
        let index = ["Home", "Movies", "TV Shows", "Search", "Settings"].firstIndex(of: name) ?? 0
        press(.up, times: 4)
        press(.left, times: 5)
        press(.right, times: index)
        remote.press(.select)
        sleep(2)
    }

    private func seconds(_ bar: XCUIElement) throws -> Int {
        let value = try XCTUnwrap(bar.value as? String)
        return value.split(separator: ",")[0].split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    /// Back hides the controls, then leaves the player.
    private func leavePlayer(_ bar: XCUIElement) {
        press(.up)
        sleep(1)
        remote.press(.menu)
        sleep(1)
        remote.press(.menu)
        XCTAssertTrue(bar.waitForNonExistence(timeout: 15), "Back should leave the player")
        sleep(2)
    }

    func testResumeAndStartOverOnDetail() async throws {
        let server = try environment("JELLYFIN_URL")
        let username = try environment("JELLYFIN_USERNAME")
        let password = try environment("JELLYFIN_PASSWORD")
        let api = try await TestServerAPI.signIn(server: server, username: username, password: password)
        let movies = try await api.movies(startIndex: 40, count: 1)
        let movie = try XCTUnwrap(movies.first)
        try await api.setResume(movie)
        addTeardownBlock { try await api.clearPlayedState(movie) }
        let saved = Int(movie.runTimeTicks * 3 / 10 / 10_000_000)

        try launchSignedIn()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        sleep(2)
        focusFirstHomeCard(in: app)
        remote.press(.select)

        let play = app.buttons["detailPlay"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        sleep(2)
        // Continue Watching puts the most recently played first, so anything else the test user has
        // in progress can come before the seeded movie. Then the saved position below isn't its own.
        XCTAssertTrue(app.staticTexts[movie.name].exists, "The first Continue Watching card should be the seeded \(movie.name)")
        XCTAssertTrue(play.label.contains("Resume"), "Saved position should offer Resume: \(play.label)")
        let startOver = app.buttons["detailStartOver"]
        XCTAssertTrue(startOver.exists, "Saved position should offer Start Over")
        capture("paths-1-detail-resume-start-over")

        XCTAssertTrue(play.hasFocus)
        remote.press(.select)
        let bar = app.buttons["transportBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 30))
        sleep(2)
        XCTAssertLessThan(abs(try seconds(bar) - saved), 30, "Resume should start at the saved \(saved)s")
        capture("paths-2-resumed")
        leavePlayer(bar)

        XCTAssertTrue(startOver.waitForExistence(timeout: 15), "Still a saved position, so Start Over stays")
        for _ in 0..<4 where !startOver.hasFocus {
            press(.right)
        }
        XCTAssertTrue(startOver.hasFocus, "Start Over should be reachable with the remote")
        remote.press(.select)
        XCTAssertTrue(bar.waitForExistence(timeout: 30))
        sleep(2)
        XCTAssertLessThan(try seconds(bar), 30, "Start Over should start at the beginning")
        capture("paths-3-started-over")
        leavePlayer(bar)
        XCTAssertTrue(play.waitForExistence(timeout: 15))
    }

    func testGoToShowPlayOnShowAndSeasonAndBack() throws {
        try launchSignedIn()
        openTab("TV Shows")
        XCTAssertTrue(app.buttons["librarySort"].waitForExistence(timeout: 20))
        sleep(4)
        remote.press(.select)

        // Play on a show starts its next episode.
        let play = app.buttons["detailPlay"]
        let bar = app.buttons["transportBar"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Seasons"].waitForExistence(timeout: 20))
        sleep(2)
        XCTAssertTrue(play.label.contains(" S"), "Play on a show should name the episode: \(play.label)")
        capture("paths-4-show")
        XCTAssertTrue(play.hasFocus)
        remote.press(.select)
        XCTAssertTrue(bar.waitForExistence(timeout: 30), "Play on a show should start the player")
        sleep(3)
        capture("paths-5-playing-from-show")
        leavePlayer(bar)
        XCTAssertTrue(app.staticTexts["Seasons"].waitForExistence(timeout: 15), "Back should return to the show")

        // Play on a season starts its next episode.
        press(.down)
        sleep(2)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Episodes"].waitForExistence(timeout: 20))
        sleep(3)
        capture("paths-6-season")
        for _ in 0..<3 where !play.hasFocus {
            press(.up)
        }
        XCTAssertTrue(play.hasFocus, "Play on a season should be reachable")
        remote.press(.select)
        XCTAssertTrue(bar.waitForExistence(timeout: 30), "Play on a season should start the player")
        sleep(3)
        capture("paths-7-playing-from-season")
        leavePlayer(bar)
        XCTAssertTrue(app.staticTexts["Episodes"].waitForExistence(timeout: 15), "Back should return to the season")

        // An episode's Go to Show opens the show, and Back returns to that episode.
        press(.down, times: 2)
        sleep(2)
        remote.press(.select)
        let goToShow = app.buttons["detailGoToShow"]
        XCTAssertTrue(goToShow.waitForExistence(timeout: 20))
        sleep(3)
        for _ in 0..<5 where !goToShow.hasFocus {
            press(.right)
        }
        XCTAssertTrue(goToShow.hasFocus, "Go to Show should be reachable")
        capture("paths-8-episode")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Seasons"].waitForExistence(timeout: 20), "Go to Show should open the show")
        sleep(2)
        capture("paths-9-went-to-show")
        remote.press(.menu)
        XCTAssertTrue(goToShow.waitForExistence(timeout: 15), "Back should return to the episode")
        sleep(1)
        capture("paths-10-back-on-episode")
    }

    /// One value from a filter submenu, which has to change the state, then clears it again.
    private func chooseAndClear(_ row: String, filter: XCUIElement, label: String) {
        let panel = FilterPanelDriver(app: app)
        panel.open()
        panel.choose(row)
        capture("paths-\(label)-list")
        press(.down)
        remote.press(.select)
        sleep(3)
        capture("paths-\(label)-chosen")
        XCTAssertEqual(filter.value as? String, "Filtered", "Choosing from \(row) should filter")
        panel.clearFilters()
        panel.back()
        panel.close()
        XCTAssertEqual(filter.value as? String, "All")
    }

    func testYearRatingFavouritesEmptyStateAndTVShowsFilter() async throws {
        let server = try environment("JELLYFIN_URL")
        let username = try environment("JELLYFIN_USERNAME")
        let password = try environment("JELLYFIN_PASSWORD")
        // The test user keeps no favourites, so Favourites isn't offered until one exists. A very
        // high rating and one ordinary favourite together match nothing, which is the empty state.
        let api = try await TestServerAPI.signIn(server: server, username: username, password: password)
        let movies = try await api.movies(startIndex: 40, count: 1)
        let movie = try XCTUnwrap(movies.first)
        try await api.setFavorite(true, movie)
        addTeardownBlock { try await api.setFavorite(false, movie) }

        try launchSignedIn()
        openTab("Movies")
        let filter = app.buttons["libraryFilter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 20))
        sleep(4)
        press(.up)
        press(.right)
        chooseAndClear("Years", filter: filter, label: "11-year")
        chooseAndClear("Parental Ratings", filter: filter, label: "12-rating")

        let panel = FilterPanelDriver(app: app)
        panel.open()
        panel.choose("Favourites")
        panel.choose("Community Rating")
        panel.choose("9 or Higher")
        panel.back()
        panel.close()
        XCTAssertEqual(filter.value as? String, "Filtered")
        XCTAssertTrue(app.staticTexts["No Matches"].waitForExistence(timeout: 10), "Empty state should show")
        capture("paths-13-empty-state")
        let clear = app.buttons["Clear Filters"].firstMatch
        XCTAssertTrue(clear.exists)
        // From Filter, at the top right. Try what a person would before calling it unreachable.
        var route: [String] = []
        for (name, move) in [("down", XCUIRemote.Button.down), ("down", .down), ("left", .left), ("down", .down)] where !app.buttons["emptyClearFilters"].hasFocus {
            press(move)
            sleep(1)
            route.append(name)
            capture("paths-13b-\(route.count)-\(name)")
        }
        print("EMPTY-STATE route to Clear Filters: \(route) reached \(app.buttons["emptyClearFilters"].hasFocus)")
        XCTAssertTrue(app.buttons["emptyClearFilters"].hasFocus, "Clear Filters should be reachable, tried \(route)")
        XCTAssertEqual(route, ["down"], "One press down should reach Clear Filters")
        remote.press(.select)
        sleep(4)
        XCTAssertEqual(filter.value as? String, "All")
        XCTAssertFalse(app.staticTexts["No Matches"].exists)
        capture("paths-14-cleared-from-empty-state")

        openTab("TV Shows")
        XCTAssertTrue(filter.waitForExistence(timeout: 20))
        sleep(4)
        press(.up)
        press(.right)
        chooseAndClear("Genres", filter: filter, label: "16-tv-genre")
    }

    func testErrorStatesOnHomeAndLibrary() throws {
        continueAfterFailure = false
        app.launchArguments = ["-FinesseFakeServer", "-FinesseFakeServerFails"]
        app.launch()
        let error = app.staticTexts["Something Went Wrong"]
        XCTAssertTrue(error.waitForExistence(timeout: 20), "Home should show its error")
        sleep(1)
        capture("paths-17-home-error")
        let tryAgain = app.buttons["Try Again"]
        XCTAssertTrue(tryAgain.exists, "The error should offer Try Again")
        for _ in 0..<3 where !tryAgain.hasFocus {
            press(.down)
        }
        XCTAssertTrue(tryAgain.hasFocus, "Try Again should be reachable")
        remote.press(.select)
        sleep(2)
        XCTAssertTrue(error.waitForExistence(timeout: 10), "Still failing, so the error should come back")

        openTab("Movies")
        XCTAssertTrue(error.waitForExistence(timeout: 10), "The library should show its error")
        sleep(1)
        capture("paths-18-library-error")
    }

    /// Something only that tab shows, so a test can't pass while sitting on another one.
    private func expectOnTab(_ tab: String, sourceLocation file: StaticString = #filePath, line: UInt = #line) {
        let marker: XCUIElement
        switch tab {
        case "Movies", "TV Shows": marker = app.staticTexts[tab]
        case "Settings": marker = app.buttons["signOut"]
        case "Search": marker = app.descendants(matching: .any)["Search"]
        default: marker = app.buttons["heroMoreInfo"]
        }
        XCTAssertTrue(marker.waitForExistence(timeout: 20), "Should be on \(tab)", file: file, line: line)
    }

    /// From content Back goes to the tab bar, staying on that tab, and from there it leaves the app.
    /// On the fake server, since leaving a tab doesn't depend on what the server holds, and it keeps
    /// these in the Fast plan with no sign-in.
    private func checkBack(from tab: String) throws {
        app.launchArguments = ["-FinesseFakeServer"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        // Presses are lost until Home has loaded and focus has settled.
        XCTAssertTrue(app.buttons["heroMoreInfo"].waitForExistence(timeout: 30))
        sleep(3)
        openTab(tab)
        sleep(2)
        expectOnTab(tab)
        press(.down)
        sleep(1)
        capture("paths-19-\(tab)-content")

        remote.press(.menu)
        sleep(2)
        capture("paths-20-\(tab)-back-once")
        XCTAssertEqual(app.state, .runningForeground, "\(tab): the first Back should stay in the app")
        expectOnTab(tab)

        for _ in 0..<2 where app.state == .runningForeground {
            remote.press(.menu)
            sleep(2)
        }
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10), "\(tab): Back from the tab bar should leave")
    }

    func testBackFromHome() throws { try checkBack(from: "Home") }
    func testBackFromMovies() throws { try checkBack(from: "Movies") }
    func testBackFromTVShows() throws { try checkBack(from: "TV Shows") }
    func testBackFromSearch() throws { try checkBack(from: "Search") }
    func testBackFromSettings() throws { try checkBack(from: "Settings") }

    /// Coming back from the Apple TV home screen shows the app again, not a blank screen.
    func testReturningFromTheHomeScreenShowsTheApp() throws {
        try launchSignedIn()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        sleep(2)
        openTab("Movies")
        expectOnTab("Movies")
        sleep(3)
        remote.press(.menu)
        sleep(2)
        for _ in 0..<2 where app.state == .runningForeground {
            remote.press(.menu)
            sleep(2)
        }
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        sleep(2)
        capture("paths-21-on-home-screen")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        for wait in [1, 3, 6] {
            sleep(UInt32(wait))
            capture("paths-22-after-return-\(wait)")
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "The app should be showing")
        remote.press(.down)
        sleep(1)
        capture("paths-23-after-return-pressed-down")
    }
}
