import Foundation
import Testing
@testable import FinEsse

/// Proves each sort and filter against the real server. Library contents can change, so these ask
/// the server what it has first, then fail rather than pass without checking anything.
private enum LiveServer {
    static let environment = ProcessInfo.processInfo.environment
    static let url = environment["JELLYFIN_URL"].flatMap(URL.init(string:))
    static let username = environment["JELLYFIN_USERNAME"]
    static let password = environment["JELLYFIN_PASSWORD"]
    static let isConfigured = url != nil && username != nil && password != nil

    static func signedInClient() async throws -> LiveJellyfinClient {
        let client = LiveJellyfinClient(
            serverURL: try #require(url),
            device: DeviceIdentity(
                clientName: "Finesse Integration Tests",
                clientVersion: "1.0",
                deviceName: "Simulator",
                // Its own, because signing in again on a device ends that user's earlier token, and
                // the other suites run alongside this one.
                deviceID: "finesse-integration-filter-tests"
            )
        )
        _ = try await client.signIn(username: try #require(username), password: try #require(password))
        return client
    }
}

@Suite(.serialized, .enabled(if: LiveServer.isConfigured, "JELLYFIN_* variables not set"))
struct LibraryFilterTests {
    private func count(_ kind: ItemKind, _ client: LiveJellyfinClient, _ change: (inout ItemFilter) -> Void = { _ in }) async throws -> Int {
        var filter = ItemFilter()
        change(&filter)
        return try await client.items(ItemQuery(kinds: [kind], filter: filter, limit: 0)).totalCount
    }

    private func ids(_ kind: ItemKind, _ sort: ItemSort, _ direction: SortDirection, _ client: LiveJellyfinClient) async throws -> [String] {
        try await client.items(ItemQuery(kinds: [kind], sort: sort, direction: direction, limit: 40)).items.map(\.id)
    }

    // MARK: Sorts

    /// Every sort offered must really reorder the library and respond to its direction. Those that
    /// depend on what the user has done are proved below.
    @Test(arguments: [ItemKind.movie, .series])
    func eachSortReordersAndReverses(kind: ItemKind) async throws {
        let client = try await LiveServer.signedInClient()
        let byName = try await ids(kind, .name, .ascending, client)
        try #require(byName.count == 40, "The test server should have at least 40 of \(kind)")
        let stateDependent: Set<ItemSort> = [.playCount, .datePlayed, .favourites, .watched]
        for sort in ItemSort.options(for: kind) where !stateDependent.contains(sort) && sort != .name {
            let forward = try await ids(kind, sort, .ascending, client)
            let backward = try await ids(kind, sort, .descending, client)
            #expect(forward != byName || backward != byName, "\(sort) on \(kind) should change the order")
            #expect(forward != backward, "\(sort) on \(kind) should respond to its direction")
        }
        try await client.signOut()
    }

    @Test func sortsPutValuesInOrder() async throws {
        let client = try await LiveServer.signedInClient()
        func values<T>(_ kind: ItemKind, _ sort: ItemSort, _ value: (MediaItem) -> T?) async throws -> [T] {
            try await client.items(ItemQuery(kinds: [kind], sort: sort, direction: .descending, limit: 30)).items.compactMap(value)
        }
        for kind in [ItemKind.movie, .series] {
            let ratings = try await values(kind, .communityRating, \.communityRating)
            try #require(ratings.count >= 2)
            #expect(ratings == ratings.sorted(by: >))
            let years = try await values(kind, .releaseYear, \.productionYear)
            try #require(years.count >= 2)
            #expect(years == years.sorted(by: >))
            let dates = try await values(kind, .releaseDate, \.premiereDate)
            try #require(dates.count >= 2)
            #expect(dates == dates.sorted(by: >))
            let lengths = try await values(kind, .runTime, \.runTime?.rawValue)
            try #require(lengths.count >= 2)
            #expect(lengths == lengths.sorted(by: >))
        }
        let critics = try await values(.movie, .criticRating, \.criticRating)
        try #require(critics.count >= 2)
        #expect(critics == critics.sorted(by: >))
        try await client.signOut()
    }

    @Test func randomGivesADifferentOrderEachTime() async throws {
        let client = try await LiveServer.signedInClient()
        let first = try await ids(.movie, .random, .ascending, client)
        let second = try await ids(.movie, .random, .ascending, client)
        #expect(first != second)
        try await client.signOut()
    }

    /// Sets real state on the last title by name, so a sort has to move it from the far end.
    @Test(arguments: [ItemKind.movie, .series])
    func stateSortsAndFiltersFollowWhatTheUserDid(kind: ItemKind) async throws {
        let client = try await LiveServer.signedInClient()
        let library = try await client.items(ItemQuery(kinds: [kind], sort: .name, direction: .descending, limit: 40)).items
        let title = try #require(library.first {
            !$0.userState.isFavorite && !$0.userState.isPlayed && $0.userState.playbackPosition == .zero
        }, "None of the last 40 titles is untouched")
        // A series is played and resumable through its episodes.
        var played = title
        var part = title
        if kind == .series {
            let episodes = try await client.items(ItemQuery(libraryID: title.id, kinds: [.episode], limit: 2)).items
            try #require(episodes.count == 2, "The series should have two episodes")
            played = episodes[0]
            part = episodes[1]
        } else {
            part = try #require(library.dropFirst().first {
                $0.id != title.id && $0.userState.playbackPosition == .zero && !$0.userState.isPlayed
            })
        }
        let runTime = try #require(part.runTime)
        let report = PlaybackReport(itemID: part.id, position: Ticks(rawValue: runTime.rawValue * 3 / 10), playMethod: .directPlay)

        func restore() async {
            _ = try? await client.setFavorite(false, itemID: title.id)
            _ = try? await client.setPlayed(false, itemID: played.id)
            _ = try? await client.setPlayed(false, itemID: part.id)
        }
        do {
            // Goes by the item rather than totals, because other suites change this user's state too.
            func found(_ id: String, _ query: ItemQuery) async throws -> Bool {
                try await client.items(query).items.contains { $0.id == id }
            }
            _ = try await client.setFavorite(true, itemID: title.id)
            #expect(try await found(title.id, ItemQuery(kinds: [kind], filter: ItemFilter(isFavorite: true), limit: 200)))
            #expect(try await found(title.id, ItemQuery(kinds: [kind], sort: .favourites, direction: .descending, limit: 200)), "Favourites first should bring it up")

            _ = try await client.setPlayed(true, itemID: played.id)
            try await client.reportPlaybackStart(report)
            try await client.reportPlaybackProgress(report)
            try await client.reportPlaybackStopped(report)

            let resumed = kind == .series ? title.id : part.id
            #expect(try await found(resumed, ItemQuery(kinds: [kind], filter: ItemFilter(isResumable: true), limit: 200)))

            // The most recent play is the series itself, or for movies the part-watched one or the played one.
            let first = kind == .series ? title.id : played.id
            let recent = kind == .series ? [title.id] : [played.id, part.id]
            let byDate = try await ids(kind, .datePlayed, .descending, client)
            #expect(byDate.prefix(2).contains { recent.contains($0) }, "Date played should bring it to the top")
            #expect(try await ids(kind, .datePlayed, .ascending, client).first != byDate.first)
            let byCount = try await client.items(ItemQuery(kinds: [kind], sort: .playCount, direction: .descending, limit: 400)).items
            #expect(byCount.contains { $0.id == first }, "Play count should bring it up from the far end")

            if kind == .movie {
                #expect(try await found(played.id, ItemQuery(kinds: [kind], filter: ItemFilter(isPlayed: true), limit: 200)))
                #expect(try await !found(played.id, ItemQuery(kinds: [kind], sort: .name, direction: .descending, filter: ItemFilter(isPlayed: false), limit: 200)))
                #expect(try await found(played.id, ItemQuery(kinds: [kind], sort: .watched, direction: .descending, limit: 200)))
            }
        } catch {
            await restore()
            throw error
        }
        await restore()
        let after = try await client.item(id: title.id)
        #expect(!after.userState.isFavorite)
        #expect(try await client.item(id: part.id).userState.playbackPosition == .zero)
        try await client.signOut()
    }

    // MARK: Filters

    /// Each on or off choice must either narrow the library, which is when the panel offers it, or
    /// match nothing, when it's hidden. One that matches everything or is ignored isn't offered.
    @Test(arguments: [ItemKind.movie, .series])
    func theOfferedChoicesReallyNarrow(kind: ItemKind) async throws {
        let client = try await LiveServer.signedInClient()
        let total = try await count(kind, client)
        let model = await LibraryModel(kind: kind, client: client)
        await model.loadFilterChoices()
        #expect(await model.choicesPhase == .loaded)

        let userState: Set<FilterChoice> = [.unwatched, .watched, .inProgress, .favourites]
        var offered: [FilterChoice] = []
        var hidden: [FilterChoice] = []
        for choice in FilterChoice.all(for: kind) {
            let matches = try await count(kind, client) { choice.toggle(in: &$0) }
            let isOffered = await model.offers(choice)
            // Other suites change this user's state, so those counts could move between the two reads.
            if !userState.contains(choice) {
                #expect(isOffered == (matches > 0 && matches < total), "\(choice) matches \(matches) of \(total), offered \(isOffered)")
            }
            if isOffered {
                offered.append(choice)
            } else {
                hidden.append(choice)
            }
        }
        print("OFFERED \(kind): \(offered.map(\.title))")
        print("HIDDEN \(kind): \(hidden.map(\.title))")
        // Fails rather than passes if these stop being checked, because a library with no subtitles
        // and one resolution isn't what this server holds.
        #expect(offered.contains(.subtitles))
        #expect(offered.contains(.fourK))
        #expect(offered.contains(.sd))
        #expect(offered.contains(.minimumRating(7)))
        try await client.signOut()
    }

    @Test func resolutionsMatchThePictureSize() async throws {
        let client = try await LiveServer.signedInClient()
        func heights(_ change: (inout ItemFilter) -> Void) async throws -> Int {
            try await count(.movie, client, change)
        }
        let fourK = try await heights { $0.is4K = true }
        let hd = try await heights { $0.isHD = true }
        let sd = try await heights { $0.isHD = false }
        try #require(fourK > 0 && hd > 0 && sd > 0, "The test server should have every resolution")
        // The server treats these as any of them.
        #expect(try await heights { $0.is4K = true; $0.isHD = true } == fourK + hd)
        #expect(try await heights { $0.is4K = true; $0.isHD = false } == fourK + sd)
        try await client.signOut()
    }

    @Test func seriesStatusFiltersAndCombines() async throws {
        let client = try await LiveServer.signedInClient()
        let continuing = try await count(.series, client) { $0.seriesStatuses = [.continuing] }
        let ended = try await count(.series, client) { $0.seriesStatuses = [.ended] }
        try #require(continuing > 0 && ended > 0, "The test server should have both")
        #expect(try await count(.series, client) { $0.seriesStatuses = [.continuing, .ended] } == continuing + ended)
        #expect(try await count(.movie, client) { $0.seriesStatuses = [.continuing] } == 0, "Why it's offered on TV Shows only")
        try await client.signOut()
    }

    /// Each list from the server: one value narrows, and two values match any of them.
    @Test(arguments: [ItemKind.movie, .series])
    func listsNarrowAndMatchAnyValue(kind: ItemKind) async throws {
        let client = try await LiveServer.signedInClient()
        let total = try await count(kind, client)
        let options = try await client.filterOptions(libraryID: nil, kinds: [kind])
        let studios = try await client.studios(libraryID: nil, kinds: [kind])
        for list in FilterList.allCases {
            let values = list.values(in: options, studios: studios)
            // Some values match nothing for this user, so go on until two do.
            var counted: [(FilterValue, Int)] = []
            for value in values.prefix(40) {
                let matches = try await count(kind, client) { list.toggle(value, in: &$0) }
                if matches > 0, matches < total {
                    counted.append((value, matches))
                }
                if counted.count == 2 { break }
            }
            try #require(counted.count == 2, "\(list) on \(kind) should have two values that narrow, from \(values.count)")
            let either = try await count(kind, client) {
                list.toggle(counted[0].0, in: &$0)
                list.toggle(counted[1].0, in: &$0)
            }
            #expect(either >= max(counted[0].1, counted[1].1), "\(list) on \(kind) should match any of them")
            #expect(either <= counted[0].1 + counted[1].1)
        }
        try await client.signOut()
    }

    @Test func differentKindsOfFilterAllHaveToMatch() async throws {
        let client = try await LiveServer.signedInClient()
        let options = try await client.filterOptions(libraryID: nil, kinds: [.movie])
        let genre = try #require(options.genres.first)
        let genreOnly = try await count(.movie, client) { $0.genres = [genre] }
        let subtitlesOnly = try await count(.movie, client) { $0.hasSubtitles = true }
        let both = try await count(.movie, client) { $0.genres = [genre]; $0.hasSubtitles = true }
        try #require(genreOnly > 0)
        #expect(both <= min(genreOnly, subtitlesOnly))
        #expect(both < genreOnly || both < subtitlesOnly)
        try await client.signOut()
    }

    @Test func returnedItemsReallyMatch() async throws {
        let client = try await LiveServer.signedInClient()
        let options = try await client.filterOptions(libraryID: nil, kinds: [.movie])
        var filter = ItemFilter()
        filter.genres = [try #require(options.genres.first)]
        filter.years = Array(options.years.prefix(10))
        let items = try await client.items(ItemQuery(kinds: [.movie], filter: filter, limit: 20)).items
        try #require(!items.isEmpty, "The newest years should have a film in that genre")
        #expect(items.allSatisfy { filter.years.contains($0.productionYear ?? 0) })

        var rated = ItemFilter()
        rated.minCommunityRating = 7
        let ratings = try await client.items(ItemQuery(kinds: [.movie], filter: rated, limit: 30)).items.compactMap(\.communityRating)
        try #require(!ratings.isEmpty)
        #expect(ratings.allSatisfy { $0 >= 7 })
        try await client.signOut()
    }

    /// The letters and # together are the whole library, which proves none is lost or counted twice.
    @Test(arguments: [ItemKind.movie, .series])
    func lettersAddUpToTheWholeLibrary(kind: ItemKind) async throws {
        let client = try await LiveServer.signedInClient()
        var sum = try await count(kind, client) { $0.name = .beforeA }
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            sum += try await count(kind, client) { $0.name = .letter(String(letter)) }
        }
        #expect(sum == (try await count(kind, client)))

        let model = await LibraryModel(kind: kind, client: client)
        await model.loadNameFilters()
        #expect(await !model.availableNameFilters.isEmpty)
        for name in await model.availableNameFilters {
            #expect(try await count(kind, client) { $0.name = name } > 0, "\(name) is offered, so it should match")
        }
        try await client.signOut()
    }

    /// The whole path a person takes: filter, page on, change the filter, page again.
    @Test func pagingStaysCorrectWhenTheFilterChanges() async throws {
        let client = try await LiveServer.signedInClient()
        let model = await LibraryModel(kind: .movie, client: client, pageSize: 20, prefetchDistance: 1)
        await model.appeared()
        await model.toggle(FilterChoice.subtitles)
        let total = await model.totalCount
        try #require(total > 40, "Needs more than two pages")
        #expect(await model.items.count == 20)
        let last = try #require(await model.items.last)
        await model.loadMore(after: last)
        #expect(await model.items.count == 40)
        #expect(Set(await model.items.map(\.id)).count == 40)

        await model.toggle(FilterChoice.fourK)
        let narrowed = await model.totalCount
        #expect(narrowed < total)
        #expect(await model.items.count == min(20, narrowed))

        await model.clearFilters()
        #expect(await !model.hasActiveFilter)
        #expect(await model.totalCount > total)
        try await client.signOut()
    }
}
