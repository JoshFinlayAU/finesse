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
