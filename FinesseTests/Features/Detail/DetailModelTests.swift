import Foundation
import Testing
@testable import FinEsse

@MainActor
@Suite struct DetailModelTests {
    private func episode(_ number: Int, played: Bool = false, position: Ticks = .zero) -> MediaItem {
        var item = MediaItem(id: "e\(number)", name: "Episode \(number)", kind: .episode)
        item.seriesID = "show"
        item.seasonID = "s1"
        item.parentIndexNumber = 1
        item.indexNumber = number
        item.userState.isPlayed = played
        item.userState.playbackPosition = position
        return item
    }

    private func makeClient(_ items: [MediaItem], nextUp: [MediaItem] = []) async throws -> InMemoryJellyfinClient {
        let client = InMemoryJellyfinClient()
        _ = try await client.signIn(username: "Test User", password: "password")
        await client.configure {
            $0.allItems = items
            $0.nextUpValue = nextUp
        }
        return client
    }

    private var show: MediaItem { MediaItem(id: "show", name: "Show", kind: .series) }

    private var season: MediaItem {
        var item = MediaItem(id: "s1", name: "Season 1", kind: .season)
        item.seriesID = "show"
        return item
    }

    @Test func moviePlaysItselfAndLoadsSimilar() async throws {
        let movie = MediaItem(id: "m", name: "Movie", kind: .movie)
        let other = MediaItem(id: "o", name: "Other", kind: .movie)
        let model = DetailModel(item: movie, client: try await makeClient([movie, other]))
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.playTarget?.id == "m")
        #expect(model.similar.map(\.id) == ["o"])
        #expect(model.playTitle == "Play")
    }

    @Test func partlyWatchedMovieResumes() async throws {
        var movie = MediaItem(id: "m", name: "Movie", kind: .movie)
        movie.userState.playbackPosition = Ticks(seconds: 60)
        let model = DetailModel(item: movie, client: try await makeClient([movie]))
        await model.load()
        #expect(model.playTitle == "Resume")
    }

    @Test func showPlaysNextUpEpisode() async throws {
        let next = episode(3)
        let model = DetailModel(item: show, client: try await makeClient([show, season, next], nextUp: [next]))
        await model.load()
        #expect(model.seasons.map(\.id) == ["s1"])
        #expect(model.playTarget?.id == "e3")
        #expect(model.playTitle == "Play S1 E3")
    }

    @Test func fullyWatchedShowOffersTheStart() async throws {
        let model = DetailModel(
            item: show,
            client: try await makeClient([show, episode(1, played: true), episode(2, played: true)])
        )
        await model.load()
        #expect(model.playTarget?.id == "e1")
    }

    @Test func seasonPlaysFirstEpisodeInProgressThenUnwatched() {
        let partial = episode(2, position: Ticks(seconds: 60))
        #expect(DetailModel.nextEpisode(in: [episode(1, played: true), partial, episode(3)])?.id == "e2")
        #expect(DetailModel.nextEpisode(in: [episode(1, played: true), episode(2)])?.id == "e2")
        #expect(DetailModel.nextEpisode(in: []) == nil)
    }

    @Test func seasonListsItsEpisodes() async throws {
        let model = DetailModel(item: season, client: try await makeClient([season, episode(1), episode(2)]))
        await model.load()
        #expect(model.episodes.map(\.id) == ["e1", "e2"])
        #expect(model.playTitle == "Play S1 E1")
    }

    @Test func episodeListsOtherEpisodesAndPlaysItself() async throws {
        let model = DetailModel(item: episode(2), client: try await makeClient([episode(1), episode(2), episode(3)]))
        await model.load()
        #expect(model.otherEpisodes.map(\.id) == ["e1", "e3"])
        #expect(model.playTarget?.id == "e2")
        #expect(model.playTitle == "Play")
    }

    @Test func togglesWatchedAndFavourite() async throws {
        let movie = MediaItem(id: "m", name: "Movie", kind: .movie)
        let model = DetailModel(item: movie, client: try await makeClient([movie]))
        await model.load()
        await model.toggleWatched()
        #expect(model.item.userState.isPlayed)
        await model.toggleWatched()
        #expect(!model.item.userState.isPlayed)
        await model.toggleFavorite()
        #expect(model.item.userState.isFavorite)
    }

    @Test func failedActionKeepsPageAndReportsIt() async throws {
        let movie = MediaItem(id: "m", name: "Movie", kind: .movie)
        let client = try await makeClient([movie])
        let model = DetailModel(item: movie, client: client)
        await model.load()
        await client.configure { $0.failure = .forbidden }
        await model.toggleFavorite()
        #expect(model.actionError != nil)
        #expect(model.phase == .loaded)
        #expect(!model.item.userState.isFavorite)
    }

    @Test func missingItemFailsThePage() async throws {
        let model = DetailModel(item: MediaItem(id: "gone", name: "Gone", kind: .movie), client: try await makeClient([]))
        await model.load()
        guard case .failed = model.phase else {
            Issue.record("Expected a failed phase")
            return
        }
    }

    @Test func refreshFailureKeepsPageShowing() async throws {
        let movie = MediaItem(id: "m", name: "Movie", kind: .movie)
        let client = try await makeClient([movie])
        let model = DetailModel(item: movie, client: client)
        await model.load()
        await client.configure { $0.failure = .network("offline") }
        await model.load()
        #expect(model.phase == .loaded)
    }

    private func gatedShow() async throws -> (DetailModel, GatedJellyfinClient) {
        var show = MediaItem(id: "show", name: "Show", kind: .series)
        show.images = ItemImages()
        var season = MediaItem(id: "season", name: "Season 1", kind: .season)
        season.seriesID = "show"
        let next = episode(1)
        let base = try await makeClient([show, season, next], nextUp: [next])
        let client = GatedJellyfinClient(base: base)
        let model = DetailModel(item: show, client: client)
        await model.load()
        #expect(model.seasons.map(\.id) == ["season"])
        #expect(model.playTarget != nil)
        return (model, client)
    }

    @Test func aFailedQuietRefreshKeepsRowsAndPlay() async throws {
        let (model, client) = try await gatedShow()
        let similar = model.similar
        let target = model.playTarget

        await client.fail(["seasons", "similar", "nextUp", "episodes"])
        await model.load()

        #expect(model.phase == .loaded)
        #expect(model.seasons.map(\.id) == ["season"])
        #expect(model.similar == similar)
        #expect(model.playTarget == target)
    }

    @Test func aCancelledRefreshKeepsRows() async throws {
        let (model, client) = try await gatedShow()
        await client.hold("seasons")
        let refresh = Task { await model.load() }
        await client.waitUntilWaiting("seasons")
        refresh.cancel()
        await client.release("seasons")
        await refresh.value

        #expect(model.phase == .loaded)
        #expect(model.seasons.map(\.id) == ["season"])
    }

    @Test func aFirstLoadCancelledHalfwayIsNotShownAsLoaded() async throws {
        var show = MediaItem(id: "show", name: "Show", kind: .series)
        show.images = ItemImages()
        let base = try await makeClient([show])
        let client = GatedJellyfinClient(base: base)
        let model = DetailModel(item: show, client: client)
        await client.hold("seasons")
        let load = Task { await model.load() }
        await client.waitUntilWaiting("seasons")
        load.cancel()
        await client.release("seasons")
        await load.value

        #expect(model.phase == .loading)
    }

    @Test func anOlderLoadFinishingLastDoesNotOverwriteANewerOne() async throws {
        let (model, client) = try await gatedShow()
        await client.hold("item")
        let older = Task { await model.load() }
        await client.waitUntilWaiting("item")

        let state = try await client.base.setPlayed(true, itemID: "show")
        #expect(state.isPlayed)
        await model.load()
        #expect(model.item.userState.isPlayed)

        await client.release("item")
        await older.value
        #expect(model.item.userState.isPlayed)
    }

    @Test func aSecondMarkWatchedWhileTheFirstIsOutIsIgnored() async throws {
        let (model, client) = try await gatedShow()
        await client.hold("setPlayed")
        let first = Task { await model.toggleWatched() }
        await client.waitUntilWaiting("setPlayed")

        await model.toggleWatched()

        await client.release("setPlayed")
        await first.value
        #expect(await client.calls["setPlayed"] == 1)
        #expect(model.item.userState.isPlayed)
    }

    @Test func aSecondFavouriteWhileTheFirstIsOutIsIgnored() async throws {
        let (model, client) = try await gatedShow()
        await client.hold("setFavorite")
        let first = Task { await model.toggleFavorite() }
        await client.waitUntilWaiting("setFavorite")

        await model.toggleFavorite()

        await client.release("setFavorite")
        await first.value
        #expect(await client.calls["setFavorite"] == 1)
        #expect(model.item.userState.isFavorite)
    }

    @Test func revokedTokenExpiresSession() async {
        let model = DetailModel(item: MediaItem(id: "m", name: "M", kind: .movie), client: InMemoryJellyfinClient())
        await model.load()
        #expect(model.sessionExpired)
    }

    @Test func metadataLine() {
        var movie = MediaItem(id: "m", name: "Movie", kind: .movie)
        movie.productionYear = 1999
        movie.runTime = Ticks(seconds: 8040)
        movie.officialRating = "M"
        movie.communityRating = 7.25
        movie.criticRating = 88
        #expect(movie.detailMetadata.first == "1999")
        #expect(movie.detailMetadata.contains("2h 14m"))
        #expect(movie.detailMetadata.contains("M"))
        #expect(movie.detailMetadata.contains("88% critics"))
        #expect(episode(4).detailMetadata == ["S1 E4"])
    }

    @Test(arguments: [(3600.0, "1h"), (5400.0, "1h 30m"), (10.0, nil), (90.0, "2m")] as [(Double, String?)])
    func runTimeText(seconds: Double, expected: String?) {
        #expect(MediaItem.runTimeText(Ticks(seconds: seconds)) == expected)
    }
}
