import XCTest

/// Captures the owner's numbered screenshot gallery. Numbers are stable, see memory/screenshot-gallery.md.
/// Skipped unless GALLERY_CAPTURE is set. Seeds only test users' own state and clears it afterwards.
/// The real user picker shows household names, so it is passed through and never captured.
@MainActor
final class GalleryCaptureUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication.forSignIn()

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            usleep(500_000)
        }
    }

    private func prepare() async throws -> TestServerAPI {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GALLERY_CAPTURE"] != nil else {
            throw XCTSkip("Only for capturing the gallery")
        }
        guard let server = environment["JELLYFIN_URL"],
              let username = environment["JELLYFIN_USERNAME"],
              let password = environment["JELLYFIN_PASSWORD"]
        else { throw XCTSkip("Test server variables are not set") }
        continueAfterFailure = false
        return try await TestServerAPI.signIn(server: server, username: username, password: password)
    }

    private func value(_ name: String) -> String {
        ProcessInfo.processInfo.environment[name] ?? ""
    }

    private func signInThroughOtherUser() {
        let other = app.buttons["otherUser"]
        XCTAssertTrue(other.waitForExistence(timeout: 20))
        focus(other, in: app)
        remote.press(.select)
        let username = app.textFields["username"]
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        enter(value("JELLYFIN_USERNAME"), into: username, in: app)
        enter(TypedPassword.first, into: app.secureTextFields["password"], in: app)
        focus(app.buttons["signIn"], in: app)
        remote.press(.select)
    }

    private func launchSignedIn() {
        app.launch()
        let tabBar = app.tabBars.firstMatch
        let address = app.textFields["serverAddress"]
        let other = app.buttons["otherUser"]
        let deadline = Date.now.addingTimeInterval(30)
        while !tabBar.exists, !address.exists, !other.exists, Date.now < deadline {
            usleep(500_000)
        }
        if !tabBar.exists {
            if address.exists {
                enter(value("JELLYFIN_URL"), into: address, in: app)
                focus(app.buttons["connect"], in: app)
                remote.press(.select)
            }
            signInThroughOtherUser()
        }
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30))
        sleep(3)
    }

    /// Up to the tab bar, back to Home, then across. Selecting a tab puts focus on its first card.
    private func openTab(_ name: String) {
        let index = ["Home", "Movies", "TV Shows", "Search", "Settings"].firstIndex(of: name) ?? 0
        press(.up, times: 8)
        press(.left, times: 5)
        press(.right, times: index)
        remote.press(.select)
        sleep(4)
    }

    private func clearAfterwards(_ api: TestServerAPI, _ items: [TestServerAPI.Movie]) {
        addTeardownBlock {
            for item in items {
                try await api.clearPlayedState(item)
            }
        }
    }

    // MARK: Sign-in. Run with the simulator keychain reset.

    func testSignIn() async throws {
        _ = try await prepare()
        app.launch()
        let address = app.textFields["serverAddress"]
        XCTAssertTrue(address.waitForExistence(timeout: 20))
        sleep(1)
        capture("g01-server-entry")
        enter(value("JELLYFIN_URL"), into: address, in: app)
        focus(app.buttons["connect"], in: app)
        remote.press(.select)

        let quickConnect = app.buttons["quickConnect"]
        XCTAssertTrue(quickConnect.waitForExistence(timeout: 20))
        focus(quickConnect, in: app)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["quickConnectCode"].waitForExistence(timeout: 20))
        sleep(1)
        capture("g02-quick-connect")
        remote.press(.menu)

        let other = app.buttons["otherUser"]
        XCTAssertTrue(other.waitForExistence(timeout: 10))
        focus(other, in: app)
        remote.press(.select)
        let username = app.textFields["username"]
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        enter(value("JELLYFIN_USERNAME"), into: username, in: app)
        capture("g03-sign-in")
        let password = app.secureTextFields["password"]
        enter("not-the-password", into: password, in: app)
        focus(app.buttons["signIn"], in: app)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Incorrect username or password."].waitForExistence(timeout: 20))
        sleep(1)
        capture("g04-sign-in-wrong-password")
        enter(TypedPassword.first, into: password, in: app)
        focus(app.buttons["signIn"], in: app)
        remote.press(.select)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
    }

    func testFakeUserPicker() async throws {
        _ = try await prepare()
        app.launchArguments = ["-FinesseFakeServer"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        sleep(1)
        focus(app.tabBars.buttons["Home"], in: app)
        press(.right, times: 4)
        remote.press(.select)
        let signOut = app.buttons["signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 10))
        sleep(1)
        focus(signOut, in: app)
        remote.press(.select)
        XCTAssertTrue(app.buttons["otherUser"].waitForExistence(timeout: 20))
        sleep(1)
        capture("g05-user-picker-fake")
    }

    // MARK: Home and libraries

    func testHomeAndLibraries() async throws {
        let api = try await prepare()
        let series = try await api.seriesWithFullFirstSeason()
        let resumed = try await api.movies(startIndex: 60, count: 2)
        let grid = try await api.movies(startIndex: 0, count: 3)
        clearAfterwards(api, series.episodes + resumed + grid)
        try await api.markPlayed(series.episodes[0])
        try await api.setResume(series.episodes[1])
        for movie in resumed {
            try await api.setResume(movie)
        }
        try await api.markPlayed(grid[1])
        try await api.setResume(grid[2])

        launchSignedIn()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        sleep(3)
        capture("g06-home")
        press(.down)
        sleep(1)
        capture("g07-home-focused-card")
        remote.press(.select, forDuration: 2)
        sleep(1)
        capture("g08-card-menu")
        remote.press(.menu)
        sleep(1)

        openTab("Movies")
        XCTAssertTrue(app.buttons["librarySort"].waitForExistence(timeout: 20))
        sleep(2)
        capture("g09-movies-grid")
        press(.right)
        sleep(1)
        capture("g10-watched-badge")
        press(.left)
        press(.up)
        sleep(1)
        remote.press(.select)
        sleep(2)
        capture("g12-sort-menu")
        remote.press(.menu)
        sleep(1)
        press(.right)
        remote.press(.select)
        sleep(2)
        capture("g13-filter-menu")
        remote.press(.menu)
        sleep(1)

        openTab("TV Shows")
        XCTAssertTrue(app.buttons["librarySort"].waitForExistence(timeout: 20))
        sleep(2)
        capture("g11-tv-grid")
    }

    // MARK: Detail

    func testDetail() async throws {
        let api = try await prepare()
        let series = try await api.seriesWithFullFirstSeason()
        clearAfterwards(api, series.episodes)
        try await api.markPlayed(series.episodes[0])
        try await api.setResume(series.episodes[1])

        launchSignedIn()
        openTab("Movies")
        XCTAssertTrue(app.buttons["librarySort"].waitForExistence(timeout: 20))
        sleep(2)
        remote.press(.select)
        XCTAssertTrue(app.buttons["detailWatched"].waitForExistence(timeout: 20))
        sleep(3)
        capture("g14-movie-detail")
        press(.down)
        sleep(2)
        capture("g15-cast-row")
        press(.down)
        sleep(2)
        capture("g16-more-like-this")
        remote.press(.menu)
        XCTAssertTrue(app.buttons["librarySort"].waitForExistence(timeout: 10))
        sleep(1)

        openTab("TV Shows")
        XCTAssertTrue(app.buttons["librarySort"].waitForExistence(timeout: 20))
        sleep(2)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Seasons"].waitForExistence(timeout: 20))
        sleep(3)
        capture("g17-show-detail")
        press(.down)
        sleep(2)
        capture("g18-seasons-row")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Episodes"].waitForExistence(timeout: 20))
        sleep(3)
        capture("g19-season-detail")
        press(.down)
        sleep(2)
        capture("g20-season-episodes")
        remote.press(.select)
        XCTAssertTrue(app.buttons["detailGoToShow"].waitForExistence(timeout: 20))
        sleep(3)
        capture("g21-episode-detail")
        press(.down)
        sleep(2)
        capture("g22-more-in-season")
    }

    // MARK: Search and Settings

    func testSearchAndSettings() async throws {
        _ = try await prepare()
        launchSignedIn()
        openTab("Search")
        capture("g23-search-empty")
        press(.down)
        app.typeText("Street")
        sleep(5)
        capture("g24-search-typed")
        press(.down, times: 5)
        sleep(2)
        capture("g25-search-results")
        openTab("Settings")
        XCTAssertTrue(app.buttons["signOut"].waitForExistence(timeout: 10))
        sleep(1)
        capture("g26-settings")
    }

    // MARK: Player

    /// A real file with two audio tracks and subtitles, the same one the track tests use.
    func testPlayerControlsAndMenus() async throws {
        let api = try await prepare()
        let data = try await TestServerAPI.send(
            "GET",
            "\(api.server)/Items/5591e677a09876112cf8ae42bf6c4e6f?userId=\(api.userID)",
            token: api.token,
            body: nil
        )
        let item = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let name = try XCTUnwrap(item?["Name"] as? String)
        let ticks = try XCTUnwrap((item?["RunTimeTicks"] as? NSNumber)?.int64Value)
        clearAfterwards(api, [.init(id: "5591e677a09876112cf8ae42bf6c4e6f", name: name, runTimeTicks: ticks)])

        launchSignedIn()
        openTab("Search")
        press(.down)
        app.typeText(name)
        sleep(5)
        press(.down, times: 5)
        sleep(2)
        remote.press(.select)
        let play = app.buttons["detailPlay"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        sleep(1)
        remote.press(.select)

        let bar = app.buttons["transportBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 30))
        sleep(2)
        capture("g27-player-controls")
        press(.right, times: 3)
        capture("g28-player-scrubbing")
        sleep(3)
        remote.press(.select)
        sleep(1)
        capture("g29-player-paused")
        remote.press(.playPause)
        sleep(1)

        // Down to the track buttons. Left and right scrub while the bar has focus.
        let onButtons = { (bar.value as? String)?.contains("track buttons focused") == true }
        XCTAssertTrue(app.buttons["audioTracks"].waitForExistence(timeout: 5))
        for _ in 0..<5 where !onButtons() {
            press(.down)
            sleep(1)
        }
        XCTAssertTrue(onButtons())
        press(.left)
        remote.press(.select)
        sleep(2)
        capture("g30-player-audio-menu")
        remote.press(.menu)
        sleep(1)
        press(.right)
        remote.press(.select)
        sleep(2)
        capture("g31-player-subtitle-menu")
        remote.press(.menu)
        sleep(1)
        press(.up)
        remote.press(.menu)
        sleep(1)
        remote.press(.menu)
        XCTAssertTrue(bar.waitForNonExistence(timeout: 15))
    }

    /// Fake server, made-up segments and no video, because the test server has no segments.
    func testSkipButtons() async throws {
        _ = try await prepare()
        app.launchArguments = ["-FinesseFakeServer", "-FinesseSeededPlayback"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        sleep(1)
        let play = app.buttons["detailPlay"]
        for _ in 0..<4 where !play.exists {
            remote.press(.select)
            sleep(2)
            if !play.exists {
                remote.press(.down)
                sleep(1)
            }
        }
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        sleep(1)
        remote.press(.select)

        let skip = app.buttons["skipSegment"]
        XCTAssertTrue(skip.waitForExistence(timeout: 30))
        XCTAssertEqual(skip.label, "Skip Intro")
        capture("g32-skip-intro")
        remote.press(.up)
        sleep(1)
        remote.press(.select)
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        XCTAssertEqual(skip.label, "Skip Credits")
        sleep(1)
        capture("g33-skip-credits")
    }

    /// A real episode: seeded at 88 percent, the furthest the server keeps, then scrubbed to the end.
    func testUpNext() async throws {
        let api = try await prepare()
        let series = try await api.seriesWithFullFirstSeason()
        let episode = series.episodes[0]
        clearAfterwards(api, series.episodes)
        try await api.setResume(episode, ticks: episode.runTimeTicks * 88 / 100)

        launchSignedIn()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        sleep(2)
        let play = app.buttons["detailPlay"]
        let bar = app.buttons["transportBar"]
        press(.down)
        remote.press(.select)
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        sleep(1)
        remote.press(.select)
        XCTAssertTrue(bar.waitForExistence(timeout: 30))
        sleep(4)

        let remainingSeconds = Double(episode.runTimeTicks) * 0.12 / 10_000_000
        press(.right, times: max(Int(remainingSeconds / 10) - 1, 0))
        let upNext = app.buttons["upNextPlay"]
        XCTAssertTrue(upNext.waitForExistence(timeout: 120))
        sleep(2)
        capture("g34-up-next")
        remote.press(.menu)
        XCTAssertTrue(bar.waitForNonExistence(timeout: 15))
    }
}
