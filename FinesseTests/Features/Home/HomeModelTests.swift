import Foundation
import Testing
@testable import FinEsse

private func signedInClient() async -> InMemoryJellyfinClient {
    let client = InMemoryJellyfinClient()
    await client.setSession(.test())
    return client
}

private func film(_ id: String, art: Bool = true) -> MediaItem {
    var item = MediaItem.test(id)
    item.overview = "About \(id)"
    if art { item.images.backdropTags = ["b"] }
    return item
}

private func show(_ id: String) -> MediaItem {
    var item = MediaItem.test(id, kind: .series)
    item.overview = "The show \(id)"
    item.images.backdropTags = ["b"]
    item.images.logoTag = "l"
    return item
}

private func episode(_ id: String, of series: MediaItem, position: Ticks = .zero) -> MediaItem {
    var item = MediaItem.test(id, kind: .episode, position: position)
    item.name = "Secret name"
    item.overview = "Secret plot"
    item.seriesID = series.id
    item.seriesName = series.name
    item.images.primaryTag = "still"
    item.images.parentBackdropItemID = series.id
    item.images.parentBackdropTags = ["b"]
    return item
}

private actor Recorder {
    private(set) var urls: [URL] = []

    func add(_ url: URL) {
        urls.append(url)
    }
}

@MainActor
private func makeModel(_ client: InMemoryJellyfinClient, recorder: Recorder? = nil) -> HomeModel {
    HomeModel(client: client, focusDelay: .milliseconds(30), prepareArt: { await recorder?.add($0) })
}

@MainActor
private func hubs(_ model: HomeModel) -> [HomeHub] {
    guard case .loaded(let hubs) = model.state else {
        Issue.record("Expected hubs, got \(model.state)")
        return []
    }
    return hubs
}

@MainActor
struct HomeModelTests {
    @Test func rowsAreInTheAgreedOrder() async {
        let client = await signedInClient()
        await client.configure {
            $0.allItems = [.test("movie"), .test("series", kind: .series)]
            $0.nextUpValue = [.test("next", kind: .episode)]
            $0.resumeValue = [.test("resume", position: Ticks(seconds: 60))]
        }
        let model = makeModel(client)
        await model.load()
        #expect(hubs(model).map(\.kind) == [.continueWatching, .nextUp, .recentMovies, .recentShows])
    }

    @Test func recentRowsAskForTheNewestOfEachKind() async {
        let client = await signedInClient()
        await client.configure { $0.allItems = [.test("movie")] }
        await makeModel(client).load()
        let queries = await client.itemQueries
        let movies = queries.first { $0.kinds == [.movie] }
        let shows = queries.first { $0.kinds == [.series] }
        #expect(movies?.sort == .dateAdded)
        #expect(movies?.direction == .descending)
        #expect(shows?.sort == .dateEpisodeAdded)
        #expect(shows?.direction == .descending)
    }

    @Test func emptyRowsAreHidden() async {
        let client = await signedInClient()
        await client.configure { $0.allItems = [.test("movie")] }
        let model = makeModel(client)
        await model.load()
        #expect(hubs(model).map(\.kind) == [.recentMovies])
    }

    @Test func nothingToShowLoadsNoRows() async {
        let client = await signedInClient()
        await client.configure { $0.filterOptionsValue.genres = ["Drama"] }
        let model = makeModel(client)
        await model.load()
        await model.extrasSettled()
        #expect(model.state == .loaded([]))
        #expect(model.hero == nil)
    }

    @Test func totalFailureShowsAnErrorAndRetryRecovers() async {
        let client = await signedInClient()
        await client.configure { $0.failure = .network("offline") }
        let model = makeModel(client)
        await model.load()
        #expect(model.state == .failed(JellyfinError.network("offline").userMessage))

        await client.configure {
            $0.failure = nil
            $0.allItems = [.test("movie")]
        }
        await model.load()
        #expect(hubs(model).count == 1)
    }

    @Test func failedRefreshKeepsWhatIsShowing() async {
        let client = await signedInClient()
        await client.configure { $0.allItems = [.test("movie")] }
        let model = makeModel(client)
        await model.load()
        await model.extrasSettled()
        let before = model.state

        await client.configure { $0.failure = .network("offline") }
        await model.load()

        #expect(model.state == before)
    }

    @Test func loadingAgainAfterPlaybackShowsTheNewPosition() async {
        let client = await signedInClient()
        await client.configure { $0.resumeValue = [.test("film", position: Ticks(seconds: 60))] }
        let model = makeModel(client)
        await model.load()

        await client.configure { $0.resumeValue = [.test("film", position: Ticks(seconds: 600))] }
        await model.load()

        #expect(hubs(model).first?.items.first?.resumePosition == Ticks(seconds: 600))
    }

    /// The reload as the player closes and a live refresh can overlap. Whichever was asked for
    /// last must be what stays, even if the earlier one answers after it.
    @Test func aLoadThatFinishesLateDoesNotUndoANewerOne() async throws {
        let base = await signedInClient()
        await base.configure {
            $0.resumeValue = [film("before")]
            $0.allItems = [film("m")]
        }
        let gated = GatedJellyfinClient(base: base)
        let model = HomeModel(client: gated, focusDelay: .milliseconds(30), prepareArt: { _ in })

        await gated.hold("items@0")
        let older = Task { await model.load() }
        for _ in 0..<500 {
            if await gated.isWaiting("items@0") { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(await gated.isWaiting("items@0"))
        // By now the older load's Continue Watching has come back, from before the change.
        try await Task.sleep(for: .milliseconds(50))

        await base.configure { $0.resumeValue = [film("after")] }
        await model.load()
        #expect(hubs(model).first?.items.map(\.id) == ["after"])

        await gated.release("items@0")
        await older.value
        #expect(hubs(model).first?.items.map(\.id) == ["after"])
    }

    @Test func refusedTokenIsReportedAsExpired() async {
        let model = makeModel(InMemoryJellyfinClient())
        await model.load()
        #expect(model.sessionExpired)
    }

    // MARK: Further rows

    @Test func furtherRowsFollowTheMainOnes() async {
        let client = await signedInClient()
        var favourite = MediaItem.test("favourite")
        favourite.userState.isFavorite = true
        favourite.genres = ["Drama"]
        await client.configure { [favourite] in
            $0.allItems = [favourite]
            $0.filterOptionsValue.genres = ["Drama", "Empty"]
        }
        let model = makeModel(client)
        await model.load()
        await model.extrasSettled()
        #expect(hubs(model).map(\.kind) == [.recentMovies, .favourites, .genre("Drama")])
    }

    @Test func libraryRowsOnlyAppearWhenAKindHasSeveralLibraries() async {
        let client = await signedInClient()
        await client.configure {
            $0.allItems = [.test("movie")]
            $0.librariesValue = [
                Library(id: "a", name: "Films", kind: .movies),
                Library(id: "b", name: "4K Films", kind: .movies),
                Library(id: "c", name: "Shows", kind: .shows),
            ]
        }
        let model = makeModel(client)
        await model.load()
        await model.extrasSettled()
        // The fake ignores which library it's asked about, so both match.
        #expect(hubs(model).map(\.kind) == [
            .recentMovies,
            .library(id: "a", name: "Films"),
            .library(id: "b", name: "4K Films"),
        ])
    }

    @Test func furtherRowsAreNotAskedForAgainOnEveryReload() async {
        let client = await signedInClient()
        await client.configure {
            $0.allItems = [.test("movie")]
            $0.filterOptionsValue.genres = ["Drama"]
        }
        let model = makeModel(client)
        await model.load()
        await model.extrasSettled()
        let first = await client.itemQueries.count

        await model.load()
        await model.extrasSettled()
        // Only the two recent rows.
        #expect(await client.itemQueries.count == first + 2)
    }

    // MARK: Billboard

    @Test func featuredLeadsWithInProgressThenAlternatesWhatIsNew() async {
        let client = await signedInClient()
        let hubs = [
            HomeHub(kind: .continueWatching, items: [film("resume")]),
            HomeHub(kind: .recentMovies, items: [film("m1"), film("m2")]),
            HomeHub(kind: .recentShows, items: [show("s1")]),
        ]
        #expect(HomeModel.featuredItems(from: hubs, client: client).map(\.id) == ["resume", "m1", "s1", "m2"])
    }

    @Test func featuredSkipsWatchedItemsAndItemsWithoutArt() async {
        let client = await signedInClient()
        var watched = film("watched")
        watched.userState.isPlayed = true
        let hubs = [HomeHub(kind: .recentMovies, items: [watched, film("bare", art: false), film("good")])]
        #expect(HomeModel.featuredItems(from: hubs, client: client).map(\.id) == ["good"])
    }

    @Test func featuredFallsBackToItemsWithoutArtWhenNothingHasAny() async {
        let client = await signedInClient()
        let hubs = [HomeHub(kind: .recentMovies, items: [film("bare", art: false)])]
        #expect(HomeModel.featuredItems(from: hubs, client: client).map(\.id) == ["bare"])
    }

    @Test func featuredShowsOneItemFromAnySeries() async {
        let client = await signedInClient()
        let series = show("s")
        let hubs = [
            HomeHub(kind: .continueWatching, items: [
                episode("e1", of: series, position: Ticks(seconds: 5)),
                episode("e2", of: series, position: Ticks(seconds: 5)),
            ]),
        ]
        #expect(HomeModel.featuredItems(from: hubs, client: client).map(\.id) == ["e1"])
    }

    @Test func loadingShowsTheFirstFeaturedItem() async {
        let client = await signedInClient()
        await client.configure { $0.allItems = [film("a")] }
        let model = makeModel(client)
        await model.load()
        await model.heroSettled()
        #expect(model.hero?.item.id == "a")
        #expect(model.hero?.overview == "About a")
        #expect(model.hero?.playTarget?.id == "a")
    }

    @Test func sweepingAlongARowOnlyLoadsWhereFocusRests() async {
        let client = await signedInClient()
        let items = [film("a"), film("b"), film("c")]
        await client.configure { $0.allItems = items }
        let recorder = Recorder()
        let model = makeModel(client, recorder: recorder)
        await model.load()
        await model.heroSettled()
        let before = await recorder.urls.count

        model.cardFocused(items[1])
        model.cardFocused(items[2])
        await model.heroSettled()

        #expect(model.hero?.item.id == "c")
        #expect(await recorder.urls.count == before + 1)
    }

    @Test func aFocusedCardOffersNoPlayButtonOfItsOwn() async {
        let client = await signedInClient()
        let item = film("a")
        await client.configure { $0.allItems = [item] }
        let model = makeModel(client)
        model.cardFocused(item)
        await model.heroSettled()
        #expect(model.hero?.playTarget == nil)
    }

    @Test func theButtonsStayOnTheFeaturedItemWhileACardHasFocus() async {
        let client = await signedInClient()
        let items = [film("a"), film("b")]
        await client.configure { $0.allItems = items }
        let model = makeModel(client)
        await model.load()
        await model.heroSettled()
        let featured = model.featuredHero?.item.id

        let other = items.first { $0.id != featured }!
        model.cardFocused(other)
        await model.heroSettled()

        #expect(model.hero?.item.id == other.id)
        #expect(model.featuredHero?.item.id == featured)
        #expect(model.featuredHero?.playTarget?.id == featured)
    }

    @Test func aReloadWhileACardHasFocusUpdatesWhatTheButtonsPlay() async {
        let client = await signedInClient()
        let item = film("a")
        await client.configure { $0.allItems = [item] }
        let model = makeModel(client)
        await model.load()
        await model.heroSettled()
        model.cardFocused(item)
        await model.heroSettled()

        var resumed = item
        resumed.userState.playbackPosition = Ticks(seconds: 60)
        await client.configure { [resumed] in $0.resumeValue = [resumed] }
        await model.load()
        await model.heroSettled()

        #expect(model.featuredHero?.playTitle == "Resume")
        #expect(model.hero?.item.id == "a")
    }

    @Test func leavingTheRowsReturnsToTheFeaturedItem() async {
        let client = await signedInClient()
        let items = [film("a"), film("b")]
        await client.configure { $0.allItems = items }
        let model = makeModel(client)
        await model.load()
        await model.heroSettled()
        let featured = model.hero?.item.id

        let other = items.first { $0.id != featured }!
        model.cardFocused(other)
        await model.heroSettled()
        #expect(model.hero?.item.id == other.id)

        model.cardFocusEnded(other)
        await model.heroSettled()
        #expect(model.hero?.item.id == featured)
    }

    @Test func aLateFocusEndForAnotherCardIsIgnored() async {
        let client = await signedInClient()
        let items = [film("a"), film("b")]
        await client.configure { $0.allItems = items }
        let model = makeModel(client)
        await model.load()
        await model.heroSettled()

        model.cardFocused(items[1])
        model.cardFocusEnded(items[0])
        await model.heroSettled()
        #expect(model.hero?.item.id == "b")
    }

    @Test func rotatingWalksTheFeaturedItemsAndWraps() async {
        let client = await signedInClient()
        await client.configure { $0.allItems = [film("a"), film("b")] }
        let model = makeModel(client)
        await model.load()
        await model.heroSettled()
        let first = model.hero?.item.id

        model.rotateFeatured()
        await model.heroSettled()
        #expect(model.hero?.item.id != first)

        model.rotateFeatured()
        await model.heroSettled()
        #expect(model.hero?.item.id == first)
    }

    @Test func rotatingDoesNothingWhileACardHasFocus() async {
        let client = await signedInClient()
        let items = [film("a"), film("b")]
        await client.configure { $0.allItems = items }
        let model = makeModel(client)
        await model.load()
        await model.heroSettled()

        model.cardFocused(items[0])
        await model.heroSettled()
        model.rotateFeatured()
        await model.heroSettled()
        #expect(model.hero?.item.id == "a")
    }

    @Test func aReloadStaysOnTheSameFeaturedItemWithItsNewState() async {
        let client = await signedInClient()
        await client.configure { $0.allItems = [film("a"), film("b")] }
        let model = makeModel(client)
        await model.load()
        await model.heroSettled()
        model.rotateFeatured()
        await model.heroSettled()
        let shown = model.hero!.item

        var updated = shown
        updated.userState.playbackPosition = Ticks(seconds: 60)
        await client.configure { [updated] in $0.resumeValue = [updated] }
        await model.load()
        await model.heroSettled()
        #expect(model.hero?.item.id == shown.id)
        #expect(model.hero?.playTitle == "Resume")
    }

    @Test func aPlayedResumeItemOffersResume() async {
        let client = await signedInClient()
        var item = film("a")
        item.userState.playbackPosition = Ticks(seconds: 60)
        await client.configure { [item] in
            $0.allItems = [item]
            $0.resumeValue = [item]
        }
        let model = makeModel(client)
        await model.load()
        await model.heroSettled()
        #expect(model.hero?.playTitle == "Resume")
    }

    @Test func aFeaturedSeriesPlaysItsNextEpisode() async {
        let client = await signedInClient()
        let series = show("s")
        let next = episode("e", of: series)
        await client.configure {
            $0.allItems = [series, next]
            $0.nextUpValue = [next]
        }
        await client.configure { $0.nextUpValue = [] }
        let model = makeModel(client)
        await model.load()
        await model.heroSettled()
        #expect(model.hero?.item.id == "s")
        #expect(model.hero?.playTarget?.id == "e")
    }
}

struct HomeHeroContentTests {
    private func content(_ item: MediaItem, series: MediaItem? = nil) async -> HomeHeroContent {
        let client = await signedInClient()
        return HomeHeroContent(item: item, full: nil, series: series, playTarget: nil, client: client)
    }

    @Test func anUnwatchedEpisodeGivesNothingAway() async {
        let series = show("s")
        let hero = await content(episode("e", of: series), series: series)
        #expect(hero.title == series.name)
        #expect(hero.subtitle == nil)
        #expect(hero.overview == "The show s")
        #expect(hero.backdropURL?.path().contains("/Items/s/") == true)
        #expect(hero.backdropURL?.path().contains("Backdrop") == true)
    }

    @Test func anUnwatchedEpisodeWithNoSeriesRecordStillHidesItsOverview() async {
        let hero = await content(episode("e", of: show("s")), series: nil)
        #expect(hero.overview == nil)
        #expect(hero.subtitle == nil)
    }

    @Test func anEpisodeInProgressCanShowItsOwnDetails() async {
        let series = show("s")
        let hero = await content(episode("e", of: series, position: Ticks(seconds: 60)), series: series)
        #expect(hero.subtitle == "Secret name")
        #expect(hero.overview == "Secret plot")
    }

    @Test func aWatchedEpisodeCanShowItsOwnDetails() async {
        let series = show("s")
        var item = episode("e", of: series)
        item.userState.isPlayed = true
        let hero = await content(item, series: series)
        #expect(hero.overview == "Secret plot")
    }

    @Test func anEpisodeNeverUsesItsOwnStillAsTheBackdrop() async {
        var item = episode("e", of: show("s"))
        item.images.parentBackdropItemID = nil
        item.images.parentBackdropTags = []
        let hero = await content(item, series: nil)
        #expect(hero.backdropURL == nil)
    }

    @Test func anEpisodeUsesItsSeriesLogo() async {
        let series = show("s")
        let hero = await content(episode("e", of: series), series: series)
        #expect(hero.logoURL?.path().contains("/Items/s/Images/Logo") == true)
    }

    @Test func noLogoMeansTheTitleIsText() async {
        let hero = await content(film("a"))
        #expect(hero.logoURL == nil)
        #expect(hero.title == "Item a")
    }

    @Test func aPosterOnlyFilmHasNoBackdrop() async {
        var item = film("a", art: false)
        item.images.primaryTag = "p"
        let hero = await content(item)
        #expect(hero.backdropURL == nil)
    }

    @Test func theFullRecordSuppliesDetailsAndTheRowSuppliesWatchState() async {
        let client = await signedInClient()
        var row = film("a")
        row.overview = nil
        row.userState.playbackPosition = Ticks(seconds: 30)
        var full = film("a")
        full.overview = "Full overview"
        full.userState.playbackPosition = Ticks(seconds: 9)
        let hero = HomeHeroContent(item: row, full: full, series: nil, playTarget: row, client: client)
        #expect(hero.overview == "Full overview")
        #expect(hero.playTarget?.resumePosition == Ticks(seconds: 30))
        #expect(hero.playTitle == "Resume")
    }
}

struct MediaItemDisplayTests {
    @Test func episodeCardsLeadWithTheSeries() {
        var item = MediaItem.test("1", kind: .episode)
        item.seriesName = "Show"
        item.name = "Pilot"
        item.parentIndexNumber = 1
        item.indexNumber = 2
        #expect(item.cardTitle == "Show")
        #expect(item.cardSubtitle == "S1 E2 · Pilot")
    }

    @Test func watchedFractionUsesPercentageThenRuntime() {
        var item = MediaItem.test("1", position: Ticks(seconds: 30))
        item.runTime = Ticks(seconds: 120)
        #expect(item.watchedFraction == 0.25)
        item.userState.playedPercentage = 50
        #expect(item.watchedFraction == 0.5)
        item.userState.isPlayed = true
        #expect(item.watchedFraction == nil)
    }

    @Test func noPositionMeansPlayFromTheStart() {
        #expect(MediaItem.test("1").resumePosition == nil)
        #expect(MediaItem.test("1", position: Ticks(seconds: 5)).resumePosition == Ticks(seconds: 5))
    }
}
