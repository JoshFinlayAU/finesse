import XCTest

/// The sort, the filters and the All or Unwatched switch are still there after the app is ended
/// and opened again, for that library only. On the fake server, so it needs no sign-in. It puts
/// Movies back to All and Name afterwards, because other fake-server tests expect that.
@MainActor
final class LibraryPreferencesUITests: XCTestCase {
    private var remote: XCUIRemote { .shared }
    private let app = XCUIApplication()
    private lazy var panel = FilterPanelDriver(app: app)

    private var sort: XCUIElement { app.buttons["librarySort"] }
    private var filter: XCUIElement { app.buttons["libraryFilter"] }
    private var all: XCUIElement { app.buttons["libraryScopeAll"] }
    private var unwatched: XCUIElement { app.buttons["libraryScopeUnwatched"] }
    private var count: XCUIElement { app.staticTexts["libraryCount"] }

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            usleep(500_000)
        }
    }

    private func launch() {
        app.launchArguments = ["-FinesseFakeServer"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        // Presses are lost until Home has loaded and focus has settled.
        XCTAssertTrue(app.buttons["heroMoreInfo"].waitForExistence(timeout: 30))
        sleep(3)
    }

    private func openTab(_ name: String) {
        let index = ["Home", "Movies", "TV Shows", "Search", "Settings"].firstIndex(of: name) ?? 0
        press(.up, times: 4)
        press(.left, times: 5)
        press(.right, times: index)
        remote.press(.select)
        sleep(2)
        XCTAssertTrue(sort.waitForExistence(timeout: 20), "\(name) should show its library")
        XCTAssertTrue(count.waitForExistence(timeout: 20), "\(name) should finish loading")
        sleep(2)
    }

    /// Along the row above the grid, by position, since Sort is a Menu and reports no focus of its
    /// own. From the tab bar it goes down, from the grid back up, and along the row toward the target.
    private func focusInTopRow(_ target: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(target.waitForExistence(timeout: 10), "\(target.identifier) should exist", file: file, line: line)
        var trail: [String] = []
        for _ in 0..<14 where !target.hasFocus {
            let now = focused
            let frame = now.exists ? now.frame : .null
            trail.append(now.exists ? "\(now.identifier.isEmpty ? now.label : now.identifier)@\(Int(frame.midX)),\(Int(frame.midY))" : "none")
            if now.exists, app.tabBars.buttons[now.label].exists {
                press(.down)
            } else if now.exists, frame.minY > filter.frame.maxY + 40 {
                press(.up)
            } else if now.exists, frame.midX > target.frame.midX {
                press(.left)
            } else {
                press(.right)
            }
        }
        if !target.hasFocus {
            capture("library-scope-unreachable")
            print("LIBRARY focus trail toward \(target.identifier) at \(target.frame): \(trail.joined(separator: " > "))")
        }
        XCTAssertTrue(target.hasFocus, "\(target.identifier) should be reachable in the top row; went \(trail.joined(separator: " > "))", file: file, line: line)
    }

    private func choose(_ target: XCUIElement) {
        focusInTopRow(target)
        remote.press(.select)
        sleep(2)
    }

    /// Sort is one press left of Filter.
    private func chooseSort(_ title: String, moving direction: XCUIRemote.Button) {
        focusInTopRow(filter)
        press(.left)
        remote.press(.select)
        sleep(2)
        panel.chooseInMenu(title, moving: direction)
        sleep(2)
        XCTAssertEqual(sort.value as? String, title)
    }

    private func expect(scope expected: XCUIElement, sortedBy title: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(expected.value as? String, "On", "\(message): \(expected.identifier) should be on", file: file, line: line)
        let other = expected.identifier == all.identifier ? unwatched : all
        XCTAssertEqual(other.value as? String, "Off", "\(message): \(other.identifier) should be off", file: file, line: line)
        XCTAssertEqual(sort.value as? String, title, "\(message): the sort", file: file, line: line)
        let isUnwatched = expected.identifier == unwatched.identifier
        XCTAssertEqual(count.label.contains("Unwatched"), isUnwatched, "\(message): the count reads \(count.label)", file: file, line: line)
        XCTAssertEqual(filter.value as? String, isUnwatched ? "Filtered" : "All", "\(message): the Filter button", file: file, line: line)
    }

    func testSortFiltersAndTheSwitchSurviveARelaunch() throws {
        continueAfterFailure = false
        launch()
        openTab("Movies")
        // Whatever an earlier run left, then the change this run makes, so the relaunch can only
        // show it if this run's save was kept.
        choose(all)
        chooseSort("Name", moving: .up)
        expect(scope: all, sortedBy: "Name", "Before")
        capture("library-scope-1-all")

        chooseSort("Date Added", moving: .down)
        choose(unwatched)
        expect(scope: unwatched, sortedBy: "Date Added", "After choosing")
        capture("library-scope-2-unwatched")

        // Ended the way the app switcher ends it, a moment after the change, as a person would.
        sleep(2)
        app.terminate()
        launch()
        openTab("Movies")
        expect(scope: unwatched, sortedBy: "Date Added", "After relaunching")
        capture("library-scope-3-relaunched")

        // Each library keeps its own.
        openTab("TV Shows")
        expect(scope: all, sortedBy: "Name", "TV Shows after relaunching")

        // Back to how other tests expect Movies, and that's kept too.
        openTab("Movies")
        choose(all)
        chooseSort("Name", moving: .up)
        expect(scope: all, sortedBy: "Name", "Put back")
    }

    /// Down from the switch reaches the grid, and Back returns to the tab bar and stays on Movies.
    func testTheSwitchHasAWayOut() throws {
        continueAfterFailure = false
        launch()
        openTab("Movies")
        choose(unwatched)
        press(.down)
        sleep(1)
        XCTAssertTrue(focused.exists, "Down from the switch should reach the grid")
        XCTAssertFalse(["libraryScopeAll", "libraryScopeUnwatched", "libraryFilter"].contains(focused.identifier), "Down from the switch should leave the top row")
        remote.press(.menu)
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "The first Back should stay in the app")
        XCTAssertTrue(app.staticTexts["Movies"].exists, "Back should stay on Movies")
        // Back to All for the other tests.
        choose(all)
        expect(scope: all, sortedBy: sort.value as? String ?? "Name", "Put back")
    }
}
