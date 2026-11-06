import Foundation
import Testing
@testable import FinEsse

@MainActor
@Suite struct LibraryFilterTests {
    private func movies(_ count: Int = 5) async throws -> InMemoryJellyfinClient {
        let client = InMemoryJellyfinClient()
        _ = try await client.signIn(username: "Test User", password: "password")
        let seeded = (0..<count).map { MediaItem(id: String(format: "%03d", $0), name: String(format: "%03d", $0), kind: .movie) }
        await client.configure { $0.allItems = seeded }
        return client
    }

    private func store(account: String = "user", kind: ItemKind = .movie) -> (LibraryPreferencesStore, UserDefaults) {
        let suite = "LibraryFilterTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (LibraryPreferencesStore(defaults: defaults, account: account, kind: kind), defaults)
    }

    // MARK: What each library offers

    @Test func moviesAndShowsOfferTheirOwnSorts() {
        let movies = ItemSort.options(for: .movie)
        let shows = ItemSort.options(for: .series)
        #expect(movies.contains(.criticRating))
        #expect(!shows.contains(.criticRating))
        #expect(movies.contains(.bitrate))
        #expect(!shows.contains(.bitrate))
        #expect(!movies.contains(.dateEpisodeAdded))
        #expect(shows.contains(.dateEpisodeAdded))
        #expect(movies.contains(.random) && shows.contains(.random))
        #expect(Set(movies).count == movies.count)
    }

    @Test func seriesStatusIsOnlyForShows() {
        let status = FilterChoice.seriesStatus(.continuing)
        #expect(FilterChoice.all(for: .series).contains(status))
        #expect(!FilterChoice.all(for: .movie).contains(status))
    }

    /// Only a choice that narrows the library is shown. One matching nothing or everything isn't.
    @Test func offersOnlyChoicesThatNarrow() async throws {
        let client = try await movies(4)
        await client.configure {
            $0.extraFilterMatch = { item, filter in
                if filter.hasSubtitles { return item.id != "000" }
                if filter.is4K { return item.id == "000" }
                if filter.hasTrailer { return false }
                return true
            }
        }
        let model = LibraryModel(kind: .movie, client: client)
        await model.loadFilterChoices()
        #expect(model.choicesPhase == .loaded)
        #expect(model.offers(.subtitles))
        #expect(model.offers(.fourK))
        #expect(!model.offers(.trailer), "Matches nothing")
        #expect(!model.offers(.threeD), "Matches everything, so it does nothing")
    }

    @Test func aChoiceThatIsOnStaysOfferedSoItCanBeTurnedOff() async throws {
        let client = try await movies(4)
        await client.configure { $0.extraFilterMatch = { _, filter in !filter.hasTrailer } }
        let (saved, _) = store()
        var preferences = LibraryPreferences()
        preferences.filter.hasTrailer = true
        saved.save(preferences)
        let model = LibraryModel(kind: .movie, client: client, preferences: saved)
        await model.loadFilterChoices()
        #expect(model.offers(.trailer))
    }

    @Test func studiosLoadWithTheOtherChoicesAndAreLeftOutIfThereAreNone() async throws {
        let client = try await movies()
        let model = LibraryModel(kind: .movie, client: client)
        await model.loadFilterChoices()
        #expect(!model.offers(FilterList.studios))
        await client.configure { $0.studiosValue = [FilterValue(id: "1", name: "A Studio")] }
        await model.loadFilterChoices()
        #expect(model.offers(FilterList.studios))
        #expect(model.values(for: .studios).map(\.name) == ["A Studio"])
    }

    @Test func aFailedLoadOffersTryAgain() async throws {
        let client = try await movies()
        await client.configure { $0.failure = .network("Offline") }
        let model = LibraryModel(kind: .movie, client: client)
        await model.loadFilterChoices()
        guard case .failed = model.choicesPhase else {
            Issue.record("Expected a failure, got \(model.choicesPhase)")
            return
        }
        await client.configure { $0.failure = nil }
        await model.loadFilterChoices()
        #expect(model.choicesPhase == .loaded)
    }

    @Test func lettersWithNoTitlesAreNotOffered() async throws {
        let client = try await movies(2)
        await client.configure {
            $0.extraFilterMatch = { _, filter in
                switch filter.name {
                case .letter("A"), .beforeA, nil: true
                default: false
                }
            }
        }
        let model = LibraryModel(kind: .movie, client: client)
        #expect(model.availableNameFilters.count == 27, "Every letter shows until they're counted")
        await model.loadNameFilters()
        #expect(model.availableNameFilters == [.beforeA, .letter("A")])
    }

    // MARK: Choosing

    @Test func choicesTheServerCantTakeTogetherReplaceEachOther() {
        var filter = ItemFilter()
        FilterChoice.watched.toggle(in: &filter)
        FilterChoice.unwatched.toggle(in: &filter)
        #expect(filter.isPlayed == false)
        FilterChoice.inProgress.toggle(in: &filter)
        #expect(filter.isPlayed == nil)
        #expect(filter.isResumable == true)
        FilterChoice.hd.toggle(in: &filter)
        FilterChoice.sd.toggle(in: &filter)
        #expect(filter.isHD == false)
        FilterChoice.minimumRating(9).toggle(in: &filter)
        FilterChoice.minimumRating(7).toggle(in: &filter)
        #expect(filter.minCommunityRating == 7)
    }

    @Test func choosingAgainTurnsItOff() {
        var filter = ItemFilter()
        for choice in FilterChoice.all(for: .series) {
            choice.toggle(in: &filter)
            #expect(choice.isOn(in: filter), "\(choice)")
            choice.toggle(in: &filter)
            #expect(!choice.isOn(in: filter), "\(choice)")
        }
        #expect(filter == ItemFilter())
    }

    @Test func listsTakeSeveralValuesAndCountEach() {
        var filter = ItemFilter()
        let action = FilterValue(id: "Action", name: "Action")
        let drama = FilterValue(id: "Drama", name: "Drama")
        FilterList.genres.toggle(action, in: &filter)
        FilterList.genres.toggle(drama, in: &filter)
        FilterList.studios.toggle(FilterValue(id: "id-1", name: "A Studio"), in: &filter)
        FilterList.years.toggle(FilterValue(id: "1999", name: "1999"), in: &filter)
        #expect(filter.genres == ["Action", "Drama"])
        #expect(filter.studios.map(\.id) == ["id-1"])
        #expect(filter.years == [1999])
        #expect(filter.activeTitles(kind: .movie).count == 4)
        FilterList.genres.toggle(action, in: &filter)
        #expect(filter.genres == ["Drama"])
    }

    @Test func aSavedValueTheServerNoLongerListsCanStillBeTurnedOff() async throws {
        let client = try await movies()
        await client.configure { $0.filterOptionsValue = FilterOptions(genres: ["Drama"]) }
        let (saved, _) = store()
        var preferences = LibraryPreferences()
        preferences.filter.genres = ["Gone"]
        saved.save(preferences)
        let model = LibraryModel(kind: .movie, client: client, preferences: saved)
        await model.loadFilterChoices()
        #expect(model.values(for: .genres).map(\.id) == ["Drama", "Gone"])
        #expect(model.selectionSummary(.genres) == "Gone")

        let gone = try #require(model.values(for: .genres).last)
        await model.toggle(gone, in: .genres)
        #expect(model.filter.genres.isEmpty)
        #expect(!model.hasActiveFilter)
        #expect(model.values(for: .genres).map(\.id) == ["Drama"])
    }

    /// Two rows with one identity leave what SwiftUI draws undefined, and they'd read the same anyway.
    @Test func theSameLanguageForAudioAndSubtitlesReadsDifferently() {
        var filter = ItemFilter()
        let english = FilterValue(id: "eng", name: "English")
        FilterList.audioLanguages.toggle(english, in: &filter)
        FilterList.subtitleLanguages.toggle(english, in: &filter)
        let titles = filter.activeTitles(kind: .movie)
        #expect(titles.count == 2)
        #expect(Set(titles).count == 2)
    }

    // MARK: Reloading

    private func gated(_ count: Int = 5) async throws -> (GatedJellyfinClient, InMemoryJellyfinClient) {
        let base = try await movies(count)
        return (GatedJellyfinClient(base: base), base)
    }

    private func waitUntilHeld(_ client: GatedJellyfinClient, _ name: String) async {
        while await !client.isWaiting(name) {
            await Task.yield()
        }
    }

    /// The panel stays up during a reload, so it mustn't say "0 titles" while it waits.
    @Test func theCountStaysDuringAReloadAndAfterAFailedOne() async throws {
        let (client, _) = try await gated()
        let model = LibraryModel(kind: .movie, client: client, pageSize: 2)
        await model.appeared()
        #expect(model.totalCount == 5)

        await client.hold("items@0")
        let toggling = Task { await model.toggle(.subtitles) }
        await waitUntilHeld(client, "items@0")
        #expect(model.phase == .loading)
        #expect(model.totalCount == 5, "Nothing has answered yet")
        await client.fail(["items@0"])
        await client.release("items@0")
        await toggling.value

        guard case .failed = model.phase else {
            Issue.record("Expected a failure, got \(model.phase)")
            return
        }
        #expect(model.totalCount == 5)
    }

    /// An answer to an older filter must not replace the newer one's, in a first page or a later one.
    @Test func anOlderFirstPageIsDropped() async throws {
        let (client, base) = try await gated()
        await base.configure { $0.extraFilterMatch = { item, filter in filter.is4K ? item.id == "000" : true } }
        let model = LibraryModel(kind: .movie, client: client, pageSize: 2)
        await model.appeared()

        await client.hold("items@0")
        let older = Task { await model.toggle(.subtitles) }
        await waitUntilHeld(client, "items@0")
        await model.toggle(.fourK)
        #expect(model.items.map(\.id) == ["000"])
        await client.release("items@0")
        await older.value
        #expect(model.items.map(\.id) == ["000"])
        #expect(model.totalCount == 1)
    }

    @Test func anOlderLaterPageIsDropped() async throws {
        let (client, base) = try await gated()
        await base.configure { $0.extraFilterMatch = { item, filter in filter.is4K ? item.id == "000" : true } }
        let model = LibraryModel(kind: .movie, client: client, pageSize: 2, prefetchDistance: 2)
        await model.appeared()

        await client.hold("items@2")
        let older = Task { await model.loadMore(after: model.items[1]) }
        await waitUntilHeld(client, "items@2")
        await model.toggle(.fourK)
        await client.release("items@2")
        await older.value
        #expect(model.items.map(\.id) == ["000"])
        #expect(!model.isLoadingMore)
    }

    /// A refresh runs each time the grid comes back, and is otherwise allowed to fail quietly.
    @Test func aRefreshNoticesAnExpiredSession() async throws {
        let client = try await movies()
        let model = LibraryModel(kind: .movie, client: client)
        await model.appeared()
        await client.configure { $0.failure = .notSignedIn }
        await model.appeared()
        #expect(model.sessionExpired)
    }

    @Test func aRefreshKeepsTheGridThroughAnyOtherFailure() async throws {
        let client = try await movies()
        let model = LibraryModel(kind: .movie, client: client)
        await model.appeared()
        await client.configure { $0.failure = .network("Offline") }
        await model.appeared()
        #expect(!model.sessionExpired)
        #expect(model.items.count == 5)
        #expect(model.phase == .loaded)
    }

    // MARK: What the server offers changes

    @Test func listsCatchUpEachTimeThePanelOpens() async throws {
        let client = try await movies()
        await client.configure {
            $0.filterOptionsValue = FilterOptions(genres: ["Drama"])
            $0.studiosValue = [FilterValue(id: "1", name: "First")]
        }
        let model = LibraryModel(kind: .movie, client: client)
        await model.loadFilterChoices()
        await client.configure {
            $0.filterOptionsValue = FilterOptions(genres: ["Drama", "Western"])
            $0.studiosValue = [FilterValue(id: "1", name: "First"), FilterValue(id: "2", name: "Second")]
        }
        await model.loadFilterChoices()
        #expect(model.values(for: .genres).map(\.id) == ["Drama", "Western"])
        #expect(model.values(for: .studios).map(\.id) == ["1", "2"])
    }

    @Test func listsAreKeptIfTheyCantBeRefreshed() async throws {
        let client = try await movies()
        await client.configure { $0.filterOptionsValue = FilterOptions(genres: ["Drama"]) }
        let model = LibraryModel(kind: .movie, client: client)
        await model.loadFilterChoices()
        await client.configure { $0.failure = .network("Offline") }
        await model.loadFilterChoices()
        #expect(model.values(for: .genres).map(\.id) == ["Drama"])
    }

    // MARK: Sorting

    @Test func theChosenSortOrdersTheGrid() async throws {
        let client = try await movies(3)
        await client.configure {
            for (index, seconds) in [100.0, 300, 200].enumerated() {
                $0.allItems[index].runTime = Ticks(seconds: seconds)
            }
        }
        let model = LibraryModel(kind: .movie, client: client)
        await model.appeared()
        await model.setSort(.runTime)
        #expect(model.items.map(\.id) == ["001", "002", "000"])
        await model.setDirection(.ascending)
        #expect(model.items.map(\.id) == ["000", "002", "001"])
    }

    @Test func inProgressOnlyMatchesWhatWasStarted() async throws {
        let client = try await movies(3)
        await client.configure { $0.allItems[1].userState.playbackPosition = Ticks(seconds: 30) }
        let model = LibraryModel(kind: .movie, client: client)
        await model.appeared()
        await model.toggle(.inProgress)
        #expect(model.items.map(\.id) == ["001"])
    }

    // MARK: Random

    private func walk(_ model: LibraryModel) async {
        var loaded = -1
        while model.hasMore, model.items.count != loaded, let last = model.items.last {
            loaded = model.items.count
            await model.loadMore(after: last)
        }
    }

    /// The server shuffles again for every request, so asking it page by page repeats and misses titles.
    @Test func randomReachesEveryTitleOnceAndKeepsItsOrder() async throws {
        let client = try await movies(50)
        let (saved, _) = store()
        var preferences = LibraryPreferences()
        preferences.sort = .random
        saved.save(preferences)
        let model = LibraryModel(kind: .movie, client: client, pageSize: 7, prefetchDistance: 1, preferences: saved)
        await model.appeared()
        await walk(model)

        #expect(model.items.count == 50)
        #expect(Set(model.items.map(\.id)).count == 50)
        #expect(!model.hasMore)
        #expect(model.items.map(\.id) != model.items.map(\.id).sorted(), "It should be a shuffle")

        // Coming back from Detail refreshes in place.
        let order = model.items.map(\.id)
        await model.appeared()
        #expect(model.items.map(\.id) == order)
    }

    @Test func onlyAskingGivesANewRandomOrder() async throws {
        let client = try await movies(50)
        let model = LibraryModel(kind: .movie, client: client, pageSize: 50)
        await model.appeared()
        await model.setSort(.random)
        let first = model.items.map(\.id)
        await model.appeared()
        #expect(model.items.map(\.id) == first)

        await model.reshuffle()
        #expect(model.items.map(\.id) != first)
        #expect(Set(model.items.map(\.id)) == Set(first))
    }

    @Test func randomKeepsToTheFilter() async throws {
        let client = try await movies(50)
        await client.configure { $0.extraFilterMatch = { item, filter in filter.is4K ? item.id < "010" : true } }
        let model = LibraryModel(kind: .movie, client: client, pageSize: 7, prefetchDistance: 1)
        await model.appeared()
        await model.setSort(.random)
        await model.toggle(.fourK)
        await walk(model)
        #expect(model.totalCount == 10)
        #expect(Set(model.items.map(\.id)) == Set((0..<10).map { String(format: "%03d", $0) }))
    }

    /// Titles deleted since the shuffle mustn't stall the grid, even a whole page of them.
    @Test func randomGetsPastTitlesDeletedSinceTheShuffle() async throws {
        let client = try await movies(20)
        let model = LibraryModel(kind: .movie, client: client, pageSize: 5, prefetchDistance: 1)
        await model.appeared()
        await model.setSort(.random)
        let kept = Set(model.items.map(\.id))
        await client.configure { fake in
            let survivors = Set((0..<20).map { String(format: "%03d", $0) }).subtracting(kept).sorted().suffix(2)
            fake.allItems = fake.allItems.filter { kept.contains($0.id) || survivors.contains($0.id) }
        }
        await walk(model)
        #expect(model.items.count == 7)
        #expect(!model.hasMore)
    }

    @Test func randomAsksForFewEnoughIDsToFitInARequest() async throws {
        let client = try await movies(400)
        let model = LibraryModel(kind: .movie, client: client, pageSize: 200, prefetchDistance: 1)
        await model.appeared()
        await model.setSort(.random)
        await walk(model)
        await model.appeared()
        #expect(model.items.count == 400)
        let largest = await client.itemQueries.map(\.ids.count).max() ?? 0
        #expect(largest > 0 && largest <= 150)
    }

    @Test func aPageOfRandomHoldsNoRepeatsAcrossTheFirstFewPages() async throws {
        let client = try await movies(50)
        let model = LibraryModel(kind: .movie, client: client, pageSize: 10, prefetchDistance: 1)
        await model.appeared()
        await model.setSort(.random)
        let first = model.items.map(\.id)
        let last = try #require(model.items.last)
        await model.loadMore(after: last)
        #expect(Array(model.items.map(\.id).prefix(10)) == first)
        #expect(model.items.count == 20, "A second page should add ten new titles")
    }

    @Test func activeFiltersAreCountedAndCleared() async throws {
        let client = try await movies()
        let model = LibraryModel(kind: .movie, client: client)
        await model.appeared()
        await model.toggle(.subtitles)
        await model.toggle(.letter("A"))
        await model.toggle(FilterValue(id: "Drama", name: "Drama"), in: .genres)
        #expect(model.activeFilterCount == 3)
        #expect(model.activeFilterTitles == ["Subtitles", "Starts with A", "Drama"])
        await model.clearFilters()
        #expect(model.activeFilterCount == 0)
        #expect(!model.hasActiveFilter)
        #expect(await client.itemQueries.last?.filter == ItemFilter())
    }

    // MARK: Long lists

    @Test func longListsGroupByLetterWithOthersFirst() {
        let values = ["Éclair", "apple", "Avocado", "Zebra", "1917", "#Tag"].map { FilterValue(id: $0, name: $0) }
        let groups = FilterLetters.groups(of: values)
        #expect(groups.map(\.letter) == ["#", "A", "E", "Z"])
        #expect(groups[0].values.map(\.name) == ["1917", "#Tag"])
        #expect(groups[1].values.map(\.name) == ["apple", "Avocado"])
    }

    // MARK: Paging

    /// A new filter starts again from the first page, so nothing from the old results remains.
    @Test func changingTheFilterStartsAgainFromTheFirstPage() async throws {
        let client = try await movies(10)
        let model = LibraryModel(kind: .movie, client: client, pageSize: 4, prefetchDistance: 1)
        await model.appeared()
        await model.loadMore(after: model.items[3])
        #expect(model.items.count == 8)

        await client.configure { $0.extraFilterMatch = { item, filter in filter.hasSubtitles ? item.id > "004" : true } }
        await model.toggle(.subtitles)
        #expect(model.items.map(\.id) == ["005", "006", "007", "008"])
        #expect(model.totalCount == 5)
        #expect(await client.itemQueries.last?.startIndex == 0)
        await model.loadMore(after: model.items[3])
        #expect(model.items.map(\.id) == ["005", "006", "007", "008", "009"])
        #expect(!model.hasMore)
    }

    @Test func countingChoicesLeavesTheGridAlone() async throws {
        let client = try await movies(10)
        let model = LibraryModel(kind: .movie, client: client, pageSize: 4)
        await model.appeared()
        let items = model.items
        await model.loadFilterChoices()
        await model.loadNameFilters()
        #expect(model.items == items)
        #expect(model.totalCount == 10)
        #expect(model.hasMore)
    }

    // MARK: Remembering

    @Test func sortAndFiltersAreRemembered() async throws {
        let client = try await movies()
        let (saved, _) = store()
        let first = LibraryModel(kind: .movie, client: client, preferences: saved)
        await first.appeared()
        await first.setSort(.dateAdded)
        await first.setDirection(.ascending)
        await first.toggle(.subtitles)

        let second = LibraryModel(kind: .movie, client: client, preferences: saved)
        #expect(second.sort == .dateAdded)
        #expect(second.direction == .ascending)
        #expect(second.filter.hasSubtitles)
        await second.appeared()
        let query = await client.itemQueries.last
        #expect(query?.sort == .dateAdded)
        #expect(query?.filter.hasSubtitles == true)
    }

    @Test func eachUserAndLibraryRemembersSeparately() {
        let suite = "LibraryFilterTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var chosen = LibraryPreferences()
        chosen.sort = .runTime
        LibraryPreferencesStore(defaults: defaults, account: "a", kind: .movie).save(chosen)
        #expect(LibraryPreferencesStore(defaults: defaults, account: "a", kind: .movie).load() == chosen)
        #expect(LibraryPreferencesStore(defaults: defaults, account: "b", kind: .movie).load() == nil)
        #expect(LibraryPreferencesStore(defaults: defaults, account: "a", kind: .series).load() == nil)
    }

    @Test func aSavedSortThatDoesNotSuitTheLibraryFallsBack() async throws {
        let client = try await movies()
        let (saved, _) = store(kind: .series)
        var preferences = LibraryPreferences()
        preferences.sort = .criticRating
        preferences.direction = .descending
        saved.save(preferences)
        let model = LibraryModel(kind: .series, client: client, preferences: saved)
        #expect(model.sort == .name)
        #expect(model.direction == .ascending)
    }

    @Test func damagedSavedDataIsIgnored() {
        let (_, defaults) = store()
        let saved = LibraryPreferencesStore(defaults: defaults, account: "user", kind: .movie)
        defaults.set(Data("not json".utf8), forKey: "libraryPreferences.user.movie")
        #expect(saved.load() == nil)
    }
}
