import Foundation
import Observation

/// One Movies or TV Shows grid. It lives as long as the tab, so its items and scroll position
/// are still there when the user comes back from Detail.
@Observable
@MainActor
final class LibraryModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let kind: ItemKind
    private(set) var phase = Phase.loading
    private(set) var items: [MediaItem] = []
    private(set) var totalCount = 0
    private(set) var options = FilterOptions()
    private(set) var choicesPhase = Phase.loading
    private(set) var isLoadingNameFilters = false
    private(set) var sort = ItemSort.name
    private(set) var direction = SortDirection.ascending
    private(set) var filter = ItemFilter()
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailed = false
    /// Set when the server refused the token, so the app should return to sign-in.
    private(set) var sessionExpired = false

    private let client: any JellyfinClient
    private let pageSize: Int
    /// How close to the end of the loaded items focus gets before the next page is fetched.
    private let prefetchDistance: Int
    /// The server offset of the next page. Items can repeat if the library changes between pages,
    /// so this is not always `items.count`.
    private var nextIndex = 0
    private var reachedEnd = false
    /// Bumped by each new query, so a slower response to an older one is dropped.
    private var generation = 0
    /// Bumped by each page, so a refresh asked for before that page can't overwrite it.
    private var pagesApplied = 0
    /// The choices that narrow this library right now.
    private var availableChoices = Set<FilterChoice>()
    private var isLoadingChoices = false
    private var studios: [FilterValue] = []
    private var nameFilters = LibraryModel.allNameFilters
    /// One shuffle of this list's IDs. The server has no stable random order: it reshuffles for every
    /// request, so asking it page by page repeats some titles and never reaches others.
    private var randomOrder: [String] = []
    private let preferences: LibraryPreferencesStore?

    init(
        kind: ItemKind,
        client: any JellyfinClient,
        pageSize: Int = 60,
        prefetchDistance: Int = 18,
        preferences: LibraryPreferencesStore? = nil
    ) {
        self.kind = kind
        self.client = client
        self.pageSize = pageSize
        self.prefetchDistance = prefetchDistance
        self.preferences = preferences
        if let saved = preferences?.load() {
            // A sort saved by an older version may not suit this library any more.
            if ItemSort.options(for: kind).contains(saved.sort) {
                sort = saved.sort
                direction = saved.direction
            }
            filter = saved.filter
        }
    }

    var sortOptions: [ItemSort] {
        ItemSort.options(for: kind)
    }

    var hasMore: Bool {
        !reachedEnd && nextIndex < totalCount
    }

    var hasActiveFilter: Bool {
        filter != ItemFilter()
    }

    var activeFilterTitles: [String] {
        filter.activeTitles(kind: kind)
    }

    var activeFilterCount: Int {
        activeFilterTitles.count
    }

    /// Whether the panel shows a choice. One that's on stays, so it can always be turned off.
    func offers(_ choice: FilterChoice) -> Bool {
        availableChoices.contains(choice) || choice.isOn(in: filter)
    }

    func offers(_ list: FilterList) -> Bool {
        !list.values(in: options, studios: studios).isEmpty || !list.selected(in: filter).isEmpty
    }

    /// Everything in the list, plus anything saved that the server no longer lists, so it can be turned off.
    func values(for list: FilterList) -> [FilterValue] {
        let values = list.values(in: options, studios: studios)
        let known = Set(values.map(\.id))
        return values + list.selected(in: filter).filter { !known.contains($0.id) }
    }

    func selectionSummary(_ list: FilterList) -> String {
        let selected = list.selected(in: filter)
        return switch selected.count {
        case 0: "Any"
        case 1: selected[0].name
        default: "\(selected.count) Selected"
        }
    }

    var nameTitle: String {
        filter.name.map(Self.title) ?? "Any"
    }

    var availableNameFilters: [NameFilter] {
        nameFilters
    }

    static func title(of name: NameFilter) -> String {
        switch name {
        case .letter(let letter): letter
        case .beforeA: "#"
        }
    }

    /// Call each time the screen appears. The first time loads; afterwards it updates what is
    /// already showing, in place, so progress is current and the position is kept.
    func appeared() async {
        if case .loaded = phase {
            await refresh()
        } else {
            await reload()
        }
    }

    func setSort(_ sort: ItemSort) async {
        guard sort != self.sort else { return }
        self.sort = sort
        direction = sort.naturalDirection
        save()
        await reload()
    }

    func setDirection(_ direction: SortDirection) async {
        guard direction != self.direction else { return }
        self.direction = direction
        save()
        await reload()
    }

    func setFilter(_ filter: ItemFilter) async {
        guard filter != self.filter else { return }
        self.filter = filter
        save()
        await reload()
    }

    /// A new random order, the only thing besides changing the list that gives one.
    func reshuffle() async {
        guard sort == .random else { return }
        await reload()
    }

    func clearFilters() async {
        await setFilter(ItemFilter())
    }

    func toggle(_ choice: FilterChoice) async {
        var changed = filter
        choice.toggle(in: &changed)
        await setFilter(changed)
    }

    var scope: LibraryScope? {
        LibraryScope.current(in: filter)
    }

    func setScope(_ scope: LibraryScope) async {
        var changed = filter
        scope.apply(to: &changed)
        await setFilter(changed)
    }

    func toggle(_ value: FilterValue, in list: FilterList) async {
        var changed = filter
        list.toggle(value, in: &changed)
        await setFilter(changed)
    }

    func toggle(_ name: NameFilter) async {
        var changed = filter
        changed.name = changed.name == name ? nil : name
        await setFilter(changed)
    }

    private func save() {
        preferences?.save(LibraryPreferences(sort: sort, direction: direction, filter: filter))
    }

    /// Call as the filter panel opens. Asks the server about each choice, because what's worth
    /// offering differs by library and changes as the user watches and adds favourites.
    func loadFilterChoices() async {
        guard !isLoadingChoices else { return }
        isLoadingChoices = true
        defer { isLoadingChoices = false }
        if case .failed = choicesPhase {
            choicesPhase = .loading
        }
        do {
            do {
                options = try await client.filterOptions(libraryID: nil, kinds: [kind])
            } catch where !error.isSessionExpired && options != FilterOptions() {
                // What's already here is still useful. The counts below will say if the server is gone.
            }
            // Before the rows appear, so that page is never empty when it opens. Not worth failing
            // the whole panel over: without them, only the Studios row is missing.
            do {
                studios = try await client.studios(libraryID: nil, kinds: [kind])
            } catch where !error.isSessionExpired {
            }
            let total = try await count(ItemFilter())
            let choices = FilterChoice.all(for: kind)
            let counted = try await counts(of: choices) { choice in
                var filter = ItemFilter()
                choice.toggle(in: &filter)
                return filter
            }
            availableChoices = Set(choices.filter { (1..<max(total, 1)).contains(counted[$0] ?? 0) })
            choicesPhase = .loaded
        } catch {
            guard !(error is CancellationError) else { return }
            handle(error) { choicesPhase = .failed(error.userMessage) }
        }
    }

    /// Every letter shows until they're counted, so the page always has something to focus.
    func loadNameFilters() async {
        guard !isLoadingNameFilters else { return }
        isLoadingNameFilters = true
        defer { isLoadingNameFilters = false }
        do {
            let counted = try await counts(of: Self.allNameFilters) { name in
                var filter = ItemFilter()
                filter.name = name
                return filter
            }
            nameFilters = Self.allNameFilters.filter { (counted[$0] ?? 0) > 0 || filter.name == $0 }
        } catch {
            guard !(error is CancellationError) else { return }
            handle(error) {}
        }
    }

    private static let allNameFilters = [NameFilter.beforeA] + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { .letter(String($0)) }

    private func count(_ filter: ItemFilter) async throws -> Int {
        try await client.items(ItemQuery(kinds: [kind], filter: filter, limit: 0)).totalCount
    }

    /// A few at a time, so opening the panel doesn't send dozens of requests at once.
    private func counts<Key: Hashable & Sendable>(
        of keys: [Key],
        filter: @escaping @Sendable (Key) -> ItemFilter
    ) async throws -> [Key: Int] {
        let client = client
        let kind = kind
        var results: [Key: Int] = [:]
        for start in stride(from: 0, to: keys.count, by: Self.countConcurrency) {
            let batch = keys[start..<min(start + Self.countConcurrency, keys.count)]
            try await withThrowingTaskGroup(of: (Key, Int).self) { group in
                for key in batch {
                    group.addTask {
                        let query = ItemQuery(kinds: [kind], filter: filter(key), limit: 0)
                        return (key, try await client.items(query).totalCount)
                    }
                }
                for try await (key, count) in group {
                    results[key] = count
                }
            }
        }
        return results
    }

    private static let countConcurrency = 4

    func reload() async {
        generation += 1
        let current = generation
        phase = .loading
        items = []
        // Not the count: the filter panel stays up during this, and shouldn't say 0 titles.
        nextIndex = 0
        reachedEnd = false
        isLoadingMore = false
        loadMoreFailed = false
        do {
            if sort == .random {
                let matching = try await client.itemIDs(query(startIndex: 0, limit: 0))
                guard current == generation else { return }
                randomOrder = matching.shuffled()
            }
            let page = try await fetchPage(startIndex: 0)
            guard current == generation else { return }
            apply(page)
            phase = .loaded
        } catch {
            guard current == generation, !(error is CancellationError) else { return }
            handle(error) { phase = .failed(error.userMessage) }
        }
    }

    /// Call as a card appears. Fetches the next page once the user is near the end of what's loaded.
    func loadMore(after item: MediaItem) async {
        guard hasMore, !isLoadingMore, !loadMoreFailed,
              let index = items.lastIndex(where: { $0.id == item.id }),
              index >= items.count - prefetchDistance
        else { return }
        await loadNextPage()
    }

    /// The failed page's Try Again button.
    func retryLoadMore() async {
        loadMoreFailed = false
        await loadNextPage()
    }

    private func loadNextPage() async {
        let current = generation
        isLoadingMore = true
        defer {
            if current == generation {
                isLoadingMore = false
            }
        }
        do {
            let page = try await fetchPage(startIndex: nextIndex)
            guard current == generation else { return }
            apply(page)
        } catch {
            guard current == generation, !(error is CancellationError) else { return }
            handle(error) { loadMoreFailed = true }
        }
    }

    private func refresh() async {
        guard !items.isEmpty, !isLoadingMore else { return }
        let current = generation
        let pagesWhenAsked = pagesApplied
        do {
            let fresh: [MediaItem], total: Int, next: Int
            if sort == .random {
                fresh = try await randomItems(Array(randomOrder.prefix(nextIndex)))
                (total, next) = (randomOrder.count, nextIndex)
            } else {
                let page = try await client.items(query(startIndex: 0, limit: nextIndex))
                (fresh, total, next) = (page.items, page.totalCount, page.startIndex + page.items.count)
            }
            guard current == generation, !isLoadingMore, pagesWhenAsked == pagesApplied else { return }
            items = Self.unique(fresh)
            totalCount = total
            nextIndex = next
        } catch {
            // Otherwise a refresh has nothing to say: the grid that's up is still good.
            guard current == generation, !(error is CancellationError) else { return }
            handle(error) {}
        }
    }

    private struct LoadedPage {
        var items: [MediaItem]
        var totalCount: Int
        var nextIndex: Int
        var reachedEnd: Bool
    }

    private func fetchPage(startIndex: Int) async throws -> LoadedPage {
        guard sort == .random else {
            let page = try await client.items(query(startIndex: startIndex, limit: pageSize))
            return LoadedPage(
                items: page.items,
                totalCount: page.totalCount,
                nextIndex: page.startIndex + page.items.count,
                reachedEnd: page.items.isEmpty
            )
        }
        // A page of titles deleted since the shuffle would add no cards, and so never ask for the
        // next one, so this carries on until it has something.
        var next = startIndex
        var found: [MediaItem] = []
        while found.isEmpty, next < randomOrder.count {
            let slice = Array(randomOrder[next..<min(next + pageSize, randomOrder.count)])
            found = try await randomItems(slice)
            next += slice.count
        }
        return LoadedPage(items: found, totalCount: randomOrder.count, nextIndex: next, reachedEnd: next >= randomOrder.count)
    }

    /// These titles in this order, a batch at a time, because a request line can only hold so many IDs.
    private func randomItems(_ ids: [String]) async throws -> [MediaItem] {
        var byID: [String: MediaItem] = [:]
        for start in stride(from: 0, to: ids.count, by: Self.idsPerRequest) {
            let batch = Array(ids[start..<min(start + Self.idsPerRequest, ids.count)])
            let page = try await client.items(ItemQuery(kinds: [kind], ids: batch, limit: batch.count))
            for item in page.items {
                byID[item.id] = item
            }
        }
        return ids.compactMap { byID[$0] }
    }

    private static let idsPerRequest = 150

    private func apply(_ page: LoadedPage) {
        pagesApplied += 1
        items = Self.unique(items + page.items)
        totalCount = page.totalCount
        nextIndex = page.nextIndex
        reachedEnd = page.reachedEnd
    }

    private func handle(_ error: Error, otherwise: () -> Void) {
        if error.isSessionExpired {
            sessionExpired = true
        } else {
            otherwise()
        }
    }

    private func query(startIndex: Int, limit: Int) -> ItemQuery {
        ItemQuery(
            kinds: [kind],
            sort: sort,
            direction: direction,
            filter: filter,
            startIndex: startIndex,
            limit: limit
        )
    }

    private static func unique(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
