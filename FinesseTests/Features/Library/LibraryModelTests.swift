import Foundation
import Testing
@testable import FinEsse

@MainActor
@Suite struct LibraryModelTests {
    private func makeClient(count: Int = 5) async throws -> InMemoryJellyfinClient {
        let client = InMemoryJellyfinClient()
        _ = try await client.signIn(username: "Test User", password: "password")
        let seeded = (0..<count).map { MediaItem(id: String(format: "%03d", $0), name: String(format: "%03d", $0), kind: .movie) }
        await client.configure { $0.allItems = seeded }
        return client
    }

    @Test func loadsFirstPageForItsKind() async throws {
        let client = try await makeClient()
        let model = LibraryModel(kind: .movie, client: client, pageSize: 2)
        await model.appeared()
        #expect(model.phase == .loaded)
        #expect(model.items.map(\.id) == ["000", "001"])
        #expect(model.totalCount == 5)
        #expect(model.hasMore)
        #expect(await client.itemQueries.first?.kinds == [.movie])
    }

    @Test func loadsNextPageOnlyNearTheEnd() async throws {
        let client = try await makeClient(count: 10)
        let model = LibraryModel(kind: .movie, client: client, pageSize: 4, prefetchDistance: 1)
        await model.appeared()
        await model.loadMore(after: model.items[0])
        #expect(model.items.count == 4)
        await model.loadMore(after: model.items[3])
        #expect(model.items.count == 8)
        await model.loadMore(after: model.items[7])
        #expect(model.items.count == 10)
        #expect(!model.hasMore)
        let queries = await client.itemQueries.count
        await model.loadMore(after: model.items[9])
        #expect(await client.itemQueries.count == queries)
    }

    @Test func changingSortReloadsWithItsNaturalDirection() async throws {
        let client = try await makeClient()
        let model = LibraryModel(kind: .movie, client: client, pageSize: 2)
        await model.appeared()
        await model.loadMore(after: model.items[1])
        await model.setSort(.dateAdded)
        #expect(model.direction == .descending)
        #expect(model.items.count == 2)
        let last = await client.itemQueries.last
        #expect(last?.sort == .dateAdded)
        #expect(last?.direction == .descending)
        #expect(last?.startIndex == 0)
    }

    @Test func filterIsSentAndCanBeCleared() async throws {
        let client = try await makeClient()
        let model = LibraryModel(kind: .movie, client: client)
        await model.appeared()
        var filter = ItemFilter()
        filter.genres = ["Drama"]
        await model.setFilter(filter)
        #expect(model.hasActiveFilter)
        #expect(model.items.isEmpty)
        #expect(await client.itemQueries.last?.filter.genres == ["Drama"])
        await model.setFilter(ItemFilter())
        #expect(!model.hasActiveFilter)
        #expect(model.items.count == 5)
    }

    @Test func comingBackKeepsItemsAndUpdatesProgress() async throws {
        let client = try await makeClient(count: 6)
        let model = LibraryModel(kind: .movie, client: client, pageSize: 2)
        await model.appeared()
        await model.loadMore(after: model.items[1])
        #expect(model.items.count == 4)

        await client.configure { $0.allItems[1].userState.playbackPosition = Ticks(seconds: 30) }
        await model.appeared()
        #expect(model.items.count == 4)
        #expect(model.items[1].userState.playbackPosition == Ticks(seconds: 30))
        #expect(model.phase == .loaded)
        await model.loadMore(after: model.items[3])
        #expect(model.items.count == 6)
    }

    @Test func failedFirstPageShowsError() async throws {
        let client = try await makeClient()
        await client.configure { $0.failure = .server(status: 500) }
        let model = LibraryModel(kind: .movie, client: client)
        await model.appeared()
        guard case .failed = model.phase else {
            Issue.record("Expected a failed phase")
            return
        }
    }

    @Test func failedPageKeepsItemsAndCanRetry() async throws {
        let client = try await makeClient(count: 4)
        let model = LibraryModel(kind: .movie, client: client, pageSize: 2)
        await model.appeared()
        await client.configure { $0.failure = .network("offline") }
        await model.loadMore(after: model.items[1])
        #expect(model.loadMoreFailed)
        #expect(model.items.count == 2)
        #expect(model.phase == .loaded)

        await client.configure { $0.failure = nil }
        await model.retryLoadMore()
        #expect(!model.loadMoreFailed)
        #expect(model.items.count == 4)
    }

    @Test func revokedTokenExpiresSession() async {
        let model = LibraryModel(kind: .movie, client: InMemoryJellyfinClient())
        await model.appeared()
        #expect(model.sessionExpired)
    }

    /// A page finishing while a refresh is out must not be overwritten by the refresh's older,
    /// shorter answer, or its cards vanish while the next page starts after them.
    @Test func aPageThatFinishesDuringARefreshKeepsItsCards() async throws {
        let base = try await makeClient(count: 12)
        let client = GatedJellyfinClient(base: base)
        let model = LibraryModel(kind: .movie, client: client, pageSize: 4, prefetchDistance: 1)
        await model.appeared()
        #expect(model.items.count == 4)

        await client.hold("items@0")
        let refresh = Task { await model.appeared() }
        await client.waitUntilWaiting("items@0")

        await model.loadMore(after: model.items[3])
        #expect(model.items.count == 8)

        await client.release("items@0")
        await refresh.value

        #expect(model.items.map(\.id) == (0..<8).map { String(format: "%03d", $0) })
        let last = try #require(model.items.last)
        await model.loadMore(after: last)
        #expect(model.items.map(\.id) == (0..<12).map { String(format: "%03d", $0) })
    }

    /// The refresh re-reads everything up to the next offset, so removing items before it skips nothing.
    @Test func removingEarlierItemsSkipsNothingAfterARefresh() async throws {
        let client = try await makeClient(count: 20)
        let model = LibraryModel(kind: .movie, client: client, pageSize: 4, prefetchDistance: 1)
        await model.appeared()
        await model.loadMore(after: model.items[3])
        await client.configure { $0.allItems.removeFirst(2) }

        await model.appeared()
        await model.loadMore(after: model.items[7])

        #expect(model.items.map(\.id) == (2..<14).map { String(format: "%03d", $0) })
    }

    /// A refresh that comes back short has to move the next offset back too, or items that
    /// reappear later are skipped.
    @Test func aShortRefreshMovesTheNextOffsetBack() async throws {
        let client = try await makeClient(count: 10)
        let all = await client.allItems
        let model = LibraryModel(kind: .movie, client: client, pageSize: 8, prefetchDistance: 8)
        await model.appeared()
        #expect(model.items.count == 8)

        await client.configure { $0.allItems = Array(all.prefix(6)) }
        await model.appeared()
        #expect(model.items.count == 6)

        await client.configure { $0.allItems = all }
        await model.appeared()
        await model.loadMore(after: model.items[5])

        #expect(model.items.map(\.id) == (0..<10).map { String(format: "%03d", $0) })
    }

    /// Items that come back with no refresh in between are only skipped if the offset stayed high.
    @Test func itemsReturningAfterAShortRefreshAreNotSkipped() async throws {
        let client = try await makeClient(count: 12)
        let all = await client.allItems
        let model = LibraryModel(kind: .movie, client: client, pageSize: 8, prefetchDistance: 8)
        await model.appeared()

        await client.configure { $0.allItems = Array(all.prefix(6)) }
        await model.appeared()
        #expect(model.items.count == 6)

        await client.configure { $0.allItems = all }
        await model.retryLoadMore()

        #expect(model.items.map(\.id) == (0..<12).map { String(format: "%03d", $0) })
    }

    @Test func showsHaveNoRuntimeSort() async {
        let model = LibraryModel(kind: .series, client: InMemoryJellyfinClient())
        #expect(!model.sortOptions.contains(.runTime))
        #expect(LibraryModel(kind: .movie, client: InMemoryJellyfinClient()).sortOptions.contains(.runTime))
    }
}
