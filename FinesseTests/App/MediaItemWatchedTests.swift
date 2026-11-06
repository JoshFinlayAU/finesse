import Testing
@testable import FinEsse

struct MediaItemWatchedTests {
    @Test func aWatchedItemShowsTheBadgeAndNoProgress() {
        var item = MediaItem.test("1", position: Ticks(seconds: 30))
        item.runTime = Ticks(seconds: 120)
        item.userState.isPlayed = true
        #expect(item.isWatched)
        #expect(item.watchedFraction == nil)
    }

    @Test func aPartlyWatchedItemKeepsItsProgressAndNoBadge() {
        var item = MediaItem.test("1", position: Ticks(seconds: 30))
        item.runTime = Ticks(seconds: 120)
        #expect(!item.isWatched)
        #expect(item.watchedFraction == 0.25)
    }

    @Test func gridCardsFillTheWidthBetweenTheSafeAreaMargins() {
        let columns = 4.0
        let gaps = (columns - 1) * 48
        #expect(MediaCardStyle.landscapeGrid.size.width * columns + gaps == 1760)
    }
}
