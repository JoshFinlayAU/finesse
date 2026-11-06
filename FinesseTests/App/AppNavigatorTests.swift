import Testing
@testable import FinEsse

@MainActor
struct AppNavigatorTests {
    @Test func showPushesOnTheCurrentTabOnly() {
        let navigator = AppNavigator()
        navigator.selectedTab = .movies
        navigator.show(.detail(.test("1")))
        #expect(navigator.paths[.movies] == [.detail(.test("1"))])
        #expect(navigator.paths[.home] == nil)
    }

    @Test func playCarriesTheResumePosition() {
        let navigator = AppNavigator()
        navigator.play(.test("1"), resumeFrom: Ticks(seconds: 90))
        #expect(navigator.activePlayback?.item.id == "1")
        #expect(navigator.activePlayback?.resumePosition == Ticks(seconds: 90))
    }
}
