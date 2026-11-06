import Foundation
import Testing
@testable import FinEsse

@MainActor
@Suite struct SearchModelTests {
    private func makeClient() async throws -> InMemoryJellyfinClient {
        let client = InMemoryJellyfinClient()
        _ = try await client.signIn(username: "Test User", password: "password")
        await client.configure {
            $0.allItems = [
                MediaItem(id: "m", name: "Red Movie", kind: .movie),
                MediaItem(id: "e", name: "Red Episode", kind: .episode),
                MediaItem(id: "x", name: "Blue Movie", kind: .movie),
            ]
        }
        return client
    }

    @Test func groupsResultsByKindAndHidesEmptyGroups() async throws {
        let model = SearchModel(client: try await makeClient(), debounce: .zero)
        await model.search("red")
        guard case .loaded(let groups) = model.state else {
            Issue.record("Expected results")
            return
        }
        #expect(groups.map(\.title) == ["Movies", "Episodes"])
        #expect(groups[0].items.map(\.id) == ["m"])
    }

    @Test func blankTermIsIdleAndMakesNoRequest() async throws {
        let client = try await makeClient()
        let model = SearchModel(client: client, debounce: .zero)
        await model.search("   ")
        #expect(model.state == .idle)
        #expect(await client.itemQueries.isEmpty)
    }

    @Test func noMatchesIsEmptyResults() async throws {
        let model = SearchModel(client: try await makeClient(), debounce: .zero)
        await model.search("nothing")
        #expect(model.state == .loaded([]))
    }

    @Test func cancelledDuringDebounceMakesNoRequest() async throws {
        let client = try await makeClient()
        let model = SearchModel(client: client, debounce: .seconds(30))
        let task = Task { await model.search("red") }
        task.cancel()
        await task.value
        #expect(await client.itemQueries.isEmpty)
        #expect(model.state == .idle)
    }

    @Test func failureShowsMessage() async throws {
        let client = try await makeClient()
        await client.configure { $0.failure = .server(status: 500) }
        let model = SearchModel(client: client, debounce: .zero)
        await model.search("red")
        guard case .failed = model.state else {
            Issue.record("Expected a failure")
            return
        }
    }

    @Test func revokedTokenExpiresSession() async {
        let model = SearchModel(client: InMemoryJellyfinClient(), debounce: .zero)
        await model.search("red")
        #expect(model.sessionExpired)
    }
}
