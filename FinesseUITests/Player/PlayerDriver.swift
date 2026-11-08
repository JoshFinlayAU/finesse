import XCTest

/// Reads the player through its invisible surface, which reports what's showing, because XCUITest
/// can't see focus inside the full-screen cover. Up on the remote stands in for a swipe up here,
/// since XCUIRemote can't touch the touch surface.
@MainActor
struct PlayerDriver {
    let app: XCUIApplication
    private var remote: XCUIRemote { .shared }

    var bar: XCUIElement { app.buttons["transportBar"] }

    private var value: String { (bar.value as? String) ?? "" }

    var isPaused: Bool { value.contains("paused") }

    var seconds: Int {
        let time = value.split(separator: ",").first.map(String.init) ?? ""
        return time.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    /// The simulator plays through the build Mac's speakers, so the engine must report it's silent.
    func expectSilent(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitFor("silent", timeout: 10), "The engine should be silent in the simulator: \(value)", file: file, line: line)
    }

    func isShowing(_ text: String) -> Bool {
        value.contains(text)
    }

    func waitFor(_ text: String, timeout: TimeInterval = 4) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !isShowing(text), Date.now < deadline {
            usleep(200_000)
        }
        return isShowing(text)
    }

    /// From anything but a scrub: brings the bar up, moves along it, and opens the panel.
    func openPanel(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        if isShowing("hidden") {
            remote.press(.up)
            XCTAssertTrue(waitFor("bar"), "Up should show the bar", file: file, line: line)
            usleep(500_000)
        }
        // The bar remembers where focus was, so start from its main button.
        for _ in 0..<10 where !isShowing("focus main") && !isShowing("focus \(name)") {
            remote.press(.left)
            usleep(500_000)
        }
        for _ in 0..<12 where !isShowing("focus \(name)") {
            remote.press(.right)
            usleep(500_000)
        }
        XCTAssertTrue(isShowing("focus \(name)"), "Right should reach \(name): \(value)", file: file, line: line)
        remote.press(.select)
        XCTAssertTrue(waitFor("panel \(name)"), "\(name) should open: \(value)", file: file, line: line)
        usleep(500_000)
    }

    func closePanelToNothing() {
        remote.press(.menu)
        _ = waitFor("bar")
        remote.press(.menu)
        _ = waitFor("hidden")
    }
}
