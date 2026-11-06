import XCTest

/// Reviews the watched badge, progress bar and season grid on the test server. Finds a series with
/// enough episodes, seeds two of them as the test user and restores them. Skips without credentials.
@MainActor
final class CardPolishUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private lazy var app = XCUIApplication()

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    func testSeasonGridShowsWatchedAndProgress() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let server = environment["JELLYFIN_URL"],
              let username = environment["JELLYFIN_USERNAME"],
              let password = environment["JELLYFIN_PASSWORD"]
        else { throw XCTSkip("Test server variables are not set") }
        continueAfterFailure = false

        let api = try await TestServerAPI.signIn(server: server, username: username, password: password)
        let series = try await api.seriesWithFullFirstSeason()
        let watched = series.episodes[0]
        let partlyWatched = series.episodes[1]
        addTeardownBlock {
            try await api.clearPlayedState(watched)
            try await api.clearPlayedState(partlyWatched)
        }
        try await api.markPlayed(watched)
        try await api.setResume(partlyWatched)

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
            let usernameField = app.textFields["username"]
            XCTAssertTrue(usernameField.waitForExistence(timeout: 10))
            enter(username, into: usernameField, in: app)
            enter(password, into: app.secureTextFields["password"], in: app)
            focus(app.buttons["signIn"], in: app)
            remote.press(.select)
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        sleep(3)

        // Search for the series, and find its card among the results.
        focus(app.tabBars.buttons["Home"], in: app)
        for _ in 0..<3 {
            remote.press(.right)
            usleep(500_000)
        }
        sleep(1)
        remote.press(.down)
        sleep(1)
        app.typeText(series.name)
        sleep(4)
        var found = false
        for _ in 0..<10 where !found {
            remote.press(.down)
            sleep(1)
            found = focused.label == series.name
        }
        XCTAssertTrue(found, "Could not reach the card for \(series.name)")

        // Series page, its Seasons row, then the season page's episode grid.
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Seasons"].waitForExistence(timeout: 20))
        sleep(2)
        remote.press(.down)
        sleep(2)
        remote.press(.select)
        sleep(4)
        // Focus starts on the page's actions, so move down into the grid.
        remote.press(.down)
        sleep(2)
        XCTAssertTrue(app.staticTexts["Episodes"].exists, "The season page should have an episode grid")
        capture("card-1-season-grid")

        // The first episode card reports its watched state.
        XCTAssertTrue((focused.value as? String)?.contains("Watched") == true, "\(focused.label) should report Watched")
        remote.press(.right)
        sleep(1)
        XCTAssertFalse((focused.value as? String)?.contains("Watched") == true, "The partly watched episode has no badge")
        capture("card-2-partly-watched-focused")
        remote.press(.down)
        sleep(2)
        capture("card-3-season-grid-lower")
    }
}

extension TestServerAPI {
    struct SeriesToReview: Sendable {
        let name: String
        let episodes: [Movie]
    }

    /// A series whose first season has at least five episodes, none yet played or started by this user.
    func seriesWithFullFirstSeason() async throws -> SeriesToReview {
        let list = try await items("\(server)/Users/\(userID)/Items?includeItemTypes=Series&recursive=true&sortBy=SortName&limit=40")
        for series in list {
            guard let id = series["Id"] as? String, let name = series["Name"] as? String else { continue }
            let seasons = try await items("\(server)/Shows/\(id)/Seasons?userId=\(userID)")
            guard let season = seasons.first?["Id"] as? String else { continue }
            let episodes = try await items("\(server)/Shows/\(id)/Episodes?userId=\(userID)&seasonId=\(season)")
            let untouched = episodes.allSatisfy { episode in
                let state = episode["UserData"] as? [String: Any]
                return state?["Played"] as? Bool != true
                    && ((state?["PlaybackPositionTicks"] as? NSNumber)?.int64Value ?? 0) == 0
            }
            let parsed = episodes.compactMap { episode -> Movie? in
                guard let id = episode["Id"] as? String, let name = episode["Name"] as? String,
                      let ticks = (episode["RunTimeTicks"] as? NSNumber)?.int64Value
                else { return nil }
                return Movie(id: id, name: name, runTimeTicks: ticks)
            }
            if untouched, parsed.count >= 5 {
                return SeriesToReview(name: name, episodes: parsed)
            }
        }
        throw XCTSkip("No series on this server has a full, untouched first season")
    }

    func markPlayed(_ episode: Movie) async throws {
        _ = try await Self.send("POST", "\(server)/UserPlayedItems/\(episode.id)?userId=\(userID)", token: token, body: nil)
    }

    private func items(_ url: String) async throws -> [[String: Any]] {
        let data = try await Self.send("GET", url, token: token, body: nil)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["Items"] as? [[String: Any]] ?? []
    }
}
