import Foundation
import Observation

struct HomeHub: Identifiable, Equatable {
    enum Kind: Hashable {
        case continueWatching
        case nextUp
        case recentMovies
        case recentShows
        case favourites
        case library(id: String, name: String)
        case genre(String)
    }

    let kind: Kind
    let items: [MediaItem]

    var id: Kind { kind }

    var title: String {
        switch kind {
        case .continueWatching: "Continue Watching"
        case .nextUp: "Next Up"
        case .recentMovies: "Recently Added Movies"
        case .recentShows: "Recently Added TV"
        case .favourites: "Favourites"
        case .library(_, let name): "New in \(name)"
        case .genre(let name): name
        }
    }

    /// Episodes and things in progress suit 16:9 art, and everything else is a poster.
    var usesLandscapeCards: Bool {
        kind == .continueWatching || kind == .nextUp
    }
}

@Observable
@MainActor
final class HomeModel {
    enum State: Equatable {
        case loading
        case loaded([HomeHub])
        case failed(String)
    }

    private(set) var state = State.loading
    /// What the billboard is showing: the focused card, or else the featured item.
    private(set) var hero: HomeHeroContent?
    /// What the buttons act on. It stays on the featured item while a card has focus, so they're
    /// ready for when focus comes back to them.
    private(set) var featuredHero: HomeHeroContent?
    /// Set when the server refused the token, so the app should return to sign-in.
    private(set) var sessionExpired = false

    /// What the billboard takes turns showing when no card has focus.
    private(set) var featured: [MediaItem] = []
    private var featuredIndex = 0
    private var focusedCard: MediaItem?

    private let client: any JellyfinClient
    private let limit: Int
    private let extraGenreRows: Int
    private let focusDelay: Duration
    private let extrasLifetime: Duration
    private let prepareArt: @Sendable (URL) async -> Void
    private let clock = ContinuousClock()

    private var coreRows: [HomeHub] = []
    private var extras: [HomeHub] = []
    private var extrasLoadedAt: ContinuousClock.Instant?
    private var extrasTask: Task<Void, Never>?
    private var heroTask: Task<Void, Never>?
    private var featuredRefreshTask: Task<Void, Never>?
    private var details: [String: MediaItem] = [:]

    init(
        client: any JellyfinClient,
        limit: Int = 24,
        extraGenreRows: Int = 6,
        focusDelay: Duration = .milliseconds(350),
        extrasLifetime: Duration = .seconds(300),
        prepareArt: @escaping @Sendable (URL) async -> Void = { _ = try? await ImagePipeline.shared.image(for: $0) }
    ) {
        self.client = client
        self.limit = limit
        self.extraGenreRows = extraGenreRows
        self.focusDelay = focusDelay
        self.extrasLifetime = extrasLifetime
        self.prepareArt = prepareArt
    }

    // MARK: Loading

    /// Loads the rows and refreshes them quietly when some are already showing. One failing row
    /// doesn't hide the others, and the whole screen fails only when nothing could load.
    func load() async {
        if case .failed = state {
            state = .loading
        }
        let client = client
        let limit = limit
        async let resume = Self.outcome { try await client.resumeItems(limit: limit) }
        async let nextUp = Self.outcome { try await client.nextUp(limit: limit) }
        async let movies = Self.outcome {
            try await client.items(ItemQuery(kinds: [.movie], sort: .dateAdded, direction: .descending, limit: limit)).items
        }
        async let shows = Self.outcome {
            try await client.items(ItemQuery(kinds: [.series], sort: .dateEpisodeAdded, direction: .descending, limit: limit)).items
        }
        let outcomes = await [
            (HomeHub.Kind.continueWatching, resume),
            (HomeHub.Kind.nextUp, nextUp),
            (HomeHub.Kind.recentMovies, movies),
            (HomeHub.Kind.recentShows, shows),
        ]
        guard !Task.isCancelled else { return }

        let failures = outcomes.compactMap { outcome -> Error? in
            if case .failure(let error) = outcome.1 { return error }
            return nil
        }
        if failures.contains(where: \.isSessionExpired) {
            sessionExpired = true
            return
        }
        if failures.count == outcomes.count, let first = failures.first {
            // A refresh that fails keeps what's already on screen.
            if case .loaded = state { return }
            state = .failed(first.userMessage)
            return
        }
        coreRows = outcomes.compactMap { kind, outcome in
            guard case .success(let items) = outcome, !items.isEmpty else { return nil }
            return HomeHub(kind: kind, items: items)
        }
        // With nothing in the main rows, the screen says so rather than showing only the extras.
        state = .loaded(coreRows.isEmpty ? [] : coreRows + extras)
        refreshFeatured(from: coreRows)
        if !coreRows.isEmpty {
            loadExtrasIfStale()
        }
    }

    /// The rows further down change slowly and cost a request each, so a reload after every film
    /// doesn't repeat them. They arrive after the main rows and never hold those up.
    private func loadExtrasIfStale() {
        if let extrasLoadedAt, extrasLoadedAt.duration(to: clock.now) < extrasLifetime { return }
        guard extrasTask == nil else { return }
        extrasTask = Task { [weak self] in
            guard let self else { return }
            let rows = await self.loadExtras()
            self.extrasTask = nil
            guard !Task.isCancelled else { return }
            self.extras = rows
            self.extrasLoadedAt = self.clock.now
            if !self.coreRows.isEmpty {
                self.state = .loaded(self.coreRows + rows)
            }
        }
    }

    private func loadExtras() async -> [HomeHub] {
        let client = client
        let limit = limit
        async let libraries = try? client.libraries()
        async let options = try? client.filterOptions(libraryID: nil, kinds: [.movie, .series])
        let found = await libraries ?? []
        let genres = await Array((options?.genres ?? []).prefix(extraGenreRows))

        var queries: [(HomeHub.Kind, ItemQuery)] = []
        var favourite = ItemQuery(kinds: [.movie, .series], sort: .dateAdded, direction: .descending, limit: limit)
        favourite.filter.isFavorite = true
        queries.append((.favourites, favourite))

        // The Recently Added rows already cover a server with one library of each kind.
        for kind in [LibraryKind.movies, .shows] {
            let matching = found.filter { $0.kind == kind }
            guard matching.count > 1 else { continue }
            for library in matching {
                queries.append((
                    .library(id: library.id, name: library.name),
                    ItemQuery(
                        libraryID: library.id,
                        kinds: kind == .movies ? [.movie] : [.series],
                        sort: kind == .movies ? .dateAdded : .dateEpisodeAdded,
                        direction: .descending,
                        limit: limit
                    )
                ))
            }
        }
        for genre in genres {
            var query = ItemQuery(kinds: [.movie, .series], sort: .communityRating, direction: .descending, limit: limit)
            query.filter.genres = [genre]
            queries.append((.genre(genre), query))
        }

        let rows = await withTaskGroup(of: (Int, HomeHub?).self) { group in
            for (index, entry) in queries.enumerated() {
                let (kind, query) = entry
                group.addTask {
                    guard let items = try? await client.items(query).items, !items.isEmpty else { return (index, nil) }
                    return (index, HomeHub(kind: kind, items: items))
                }
            }
            var collected: [(Int, HomeHub?)] = []
            for await row in group {
                collected.append(row)
            }
            return collected
        }
        return rows.sorted { $0.0 < $1.0 }.compactMap(\.1)
    }

    private static func outcome(
        _ load: @Sendable () async throws -> [MediaItem]
    ) async -> Result<[MediaItem], Error> {
        do {
            return .success(try await load())
        } catch {
            return .failure(error)
        }
    }

    // MARK: Billboard

    /// Waits for whatever the billboard is changing to. For tests.
    func heroSettled() async {
        await heroTask?.value
        await featuredRefreshTask?.value
    }

    /// Waits for the rows further down. For tests.
    func extrasSettled() async {
        await extrasTask?.value
    }

    /// Follows a card after focus has rested on it, so sweeping along a row doesn't load each one.
    func cardFocused(_ item: MediaItem) {
        focusedCard = item
        show(item, delay: focusDelay, isFeatured: false)
    }

    /// Focus left the rows, so the billboard goes back to the featured item.
    func cardFocusEnded(_ item: MediaItem) {
        guard focusedCard?.id == item.id else { return }
        focusedCard = nil
        guard let current = currentFeatured else { return }
        show(current, delay: focusDelay, isFeatured: true)
    }

    /// Moves to the next featured item. Does nothing while a card has focus.
    func rotateFeatured() {
        guard focusedCard == nil, featured.count > 1 else { return }
        featuredIndex = (featuredIndex + 1) % featured.count
        show(featured[featuredIndex], delay: .zero, isFeatured: true)
    }

    private var currentFeatured: MediaItem? {
        featured.indices.contains(featuredIndex) ? featured[featuredIndex] : nil
    }

    /// In-progress items first, then what's new, skipping anything already watched and anything
    /// with no art to show when something else has it. Only one item from any series.
    static func featuredItems(from hubs: [HomeHub], client: any JellyfinClient, limit: Int = 6) -> [MediaItem] {
        func items(_ kind: HomeHub.Kind) -> [MediaItem] {
            hubs.first { $0.kind == kind }?.items ?? []
        }
        let movies = items(.recentMovies).filter { !$0.isWatched }
        let shows = items(.recentShows).filter { !$0.isWatched }
        var recent: [MediaItem] = []
        for index in 0..<max(movies.count, shows.count) {
            if index < movies.count { recent.append(movies[index]) }
            if index < shows.count { recent.append(shows[index]) }
        }
        var seen = Set<String>()
        let unique = (Array(items(.continueWatching).prefix(2)) + recent).filter {
            seen.insert($0.seriesID ?? $0.id).inserted
        }
        let withArt = unique.filter { client.homeBackdropURL(for: $0) != nil }
        return Array((withArt.isEmpty ? unique : withArt).prefix(limit))
    }

    /// Keeps the billboard on the same item across a reload wherever it can, with its new state.
    private func refreshFeatured(from hubs: [HomeHub]) {
        let previous = currentFeatured?.id
        featured = Self.featuredItems(from: hubs, client: client)
        if featured.isEmpty, let first = hubs.first?.items.first {
            featured = [first]
        }
        featuredIndex = featured.firstIndex { $0.id == previous } ?? 0

        if let card = focusedCard {
            let updated = hubs.lazy.flatMap(\.items).first { $0.id == card.id } ?? card
            focusedCard = updated
            show(updated, delay: .zero, isFeatured: false)
            refreshFeaturedButtons()
        } else if let current = currentFeatured {
            show(current, delay: .zero, isFeatured: true)
        } else {
            heroTask?.cancel()
            hero = nil
            featuredHero = nil
        }
    }

    /// A reload while a card has focus still has to update what the buttons will play.
    private func refreshFeaturedButtons() {
        guard let current = currentFeatured else {
            featuredHero = nil
            return
        }
        featuredRefreshTask?.cancel()
        featuredRefreshTask = Task { [weak self] in
            guard let self else { return }
            let content = await self.content(for: current, wantsPlayTarget: true)
            guard !Task.isCancelled else { return }
            self.featuredHero = content
        }
    }

    private func show(_ item: MediaItem, delay: Duration, isFeatured: Bool) {
        heroTask?.cancel()
        heroTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, let self else { return }
            let content = await self.content(for: item, wantsPlayTarget: isFeatured)
            guard !Task.isCancelled else { return }
            // Text and art change together when the art arrives in time, and a slow image
            // catches up with its own fade rather than holding the text back.
            if let url = content.backdropURL {
                await self.prepare(url)
            }
            guard !Task.isCancelled else { return }
            self.hero = content
            if isFeatured {
                self.featuredHero = content
            }
        }
    }

    private func prepare(_ url: URL) async {
        let prepareArt = prepareArt
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await prepareArt(url) }
            group.addTask { try? await Task.sleep(for: .seconds(1.2)) }
            await group.next()
            group.cancelAll()
        }
    }

    private func content(for item: MediaItem, wantsPlayTarget: Bool) async -> HomeHeroContent {
        async let full = details(forID: item.id)
        async let series = seriesDetails(for: item)
        async let target = wantsPlayTarget ? playTarget(for: item) : nil
        return await HomeHeroContent(
            item: item,
            full: full,
            series: series,
            playTarget: target,
            client: client
        )
    }

    private func seriesDetails(for item: MediaItem) async -> MediaItem? {
        guard let id = item.seriesID else { return nil }
        return await details(forID: id)
    }

    /// Details don't change while browsing, and watch state comes from the row's copy of the item.
    private func details(forID id: String) async -> MediaItem? {
        if let cached = details[id] { return cached }
        guard let loaded = try? await client.item(id: id) else { return nil }
        if details.count > 200 {
            details.removeAll()
        }
        details[id] = loaded
        return loaded
    }

    private func playTarget(for item: MediaItem) async -> MediaItem? {
        if item.isPlayable { return item }
        guard item.kind == .series else { return nil }
        if let next = try? await client.nextUp(seriesID: item.id) {
            return next
        }
        guard let all = try? await client.episodes(seriesID: item.id, seasonID: nil) else { return nil }
        return DetailModel.nextEpisode(in: all)
    }
}
