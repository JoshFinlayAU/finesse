import Foundation
import Observation

extension ItemSort {
    var title: String {
        switch self {
        case .name: "Name"
        case .dateAdded: "Date Added"
        case .releaseDate: "Release Date"
        case .communityRating: "Rating"
        case .criticRating: "Critic Rating"
        case .runTime: "Runtime"
        case .datePlayed: "Date Played"
        case .random: "Random"
        }
    }

    /// Names read A to Z. Everything else reads best with the newest or highest first.
    var naturalDirection: SortDirection {
        self == .name ? .ascending : .descending
    }
}

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

    init(kind: ItemKind, client: any JellyfinClient, pageSize: Int = 60, prefetchDistance: Int = 18) {
        self.kind = kind
        self.client = client
        self.pageSize = pageSize
        self.prefetchDistance = prefetchDistance
    }

    var sortOptions: [ItemSort] {
        var sorts: [ItemSort] = [.name, .dateAdded, .releaseDate, .communityRating]
        if kind == .movie {
            sorts += [.criticRating, .runTime]
        }
        return sorts + [.datePlayed]
    }

    var hasMore: Bool {
        !reachedEnd && nextIndex < totalCount
    }

    var hasActiveFilter: Bool {
        filter != ItemFilter()
    }

    /// Call each time the screen appears. The first time loads; afterwards it updates what is
    /// already showing, in place, so progress is current and the position is kept.
    func appeared() async {
        if case .loaded = phase {
            await refresh()
        } else {
            await reload()
        }
        if options == FilterOptions() {
            options = (try? await client.filterOptions(libraryID: nil, kinds: [kind])) ?? FilterOptions()
        }
    }

    func setSort(_ sort: ItemSort) async {
        guard sort != self.sort else { return }
        self.sort = sort
        direction = sort.naturalDirection
        await reload()
    }

    func setDirection(_ direction: SortDirection) async {
        guard direction != self.direction else { return }
        self.direction = direction
        await reload()
    }

    func setFilter(_ filter: ItemFilter) async {
        guard filter != self.filter else { return }
        self.filter = filter
        await reload()
    }

    func reload() async {
        generation += 1
        let current = generation
        phase = .loading
        items = []
        totalCount = 0
        nextIndex = 0
        reachedEnd = false
        isLoadingMore = false
        loadMoreFailed = false
        do {
            let page = try await client.items(query(startIndex: 0, limit: pageSize))
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
            let page = try await client.items(query(startIndex: nextIndex, limit: pageSize))
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
        guard let page = try? await client.items(query(startIndex: 0, limit: nextIndex)),
              current == generation, !isLoadingMore, pagesWhenAsked == pagesApplied
        else { return }
        items = Self.unique(page.items)
        totalCount = page.totalCount
        nextIndex = page.startIndex + page.items.count
    }

    private func apply(_ page: Page<MediaItem>) {
        pagesApplied += 1
        items = Self.unique(items + page.items)
        totalCount = page.totalCount
        nextIndex = page.startIndex + page.items.count
        reachedEnd = page.items.isEmpty
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
