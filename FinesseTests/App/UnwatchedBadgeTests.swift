import Testing
@testable import FinEsse

/// The count on series and season cards, from the server's UnplayedItemCount.
struct UnwatchedBadgeTests {
    private func item(_ kind: ItemKind, unplayed: Int?, played: Bool = false) -> MediaItem {
        var item = MediaItem(id: "1", name: "Show", kind: kind)
        item.userState.unplayedItemCount = unplayed
        item.userState.isPlayed = played
        return item
    }

    @Test func seriesAndSeasonsShowTheirCount() {
        #expect(item(.series, unplayed: 3).unwatchedCount == 3)
        #expect(item(.season, unplayed: 140).unwatchedCount == 140)
    }

    @Test func moviesAndEpisodesNeverShowOne() {
        #expect(item(.movie, unplayed: 3).unwatchedCount == nil)
        #expect(item(.episode, unplayed: 3).unwatchedCount == nil)
    }

    @Test func nothingLeftOrNoCountShowsNothing() {
        #expect(item(.series, unplayed: 0).unwatchedCount == nil)
        #expect(item(.series, unplayed: nil).unwatchedCount == nil)
    }

    /// The check mark shows instead.
    @Test func aWatchedSeriesShowsNoCount() {
        #expect(item(.series, unplayed: 2, played: true).unwatchedCount == nil)
    }

    @Test func theBadgeCapsAt99() {
        #expect(UnwatchedCountBadge.text(for: 7) == "7")
        #expect(UnwatchedCountBadge.text(for: 99) == "99")
        #expect(UnwatchedCountBadge.text(for: 100) == "99+")
    }

    @Test func theCountIsSpokenInWords() {
        #expect(UnwatchedCountBadge.spokenText(for: 1) == "1 unwatched episode")
        #expect(UnwatchedCountBadge.spokenText(for: 3) == "3 unwatched episodes")
    }
}
