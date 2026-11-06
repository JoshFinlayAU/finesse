import Foundation
import Observation

struct HomeHub: Identifiable, Equatable {
    enum Kind: Equatable {
        case continueWatching
        case nextUp
        case recentlyAdded
    }

    let kind: Kind
    let items: [MediaItem]

    var id: Kind { kind }

    var title: String {
        switch kind {
        case .continueWatching: "Continue Watching"
        case .nextUp: "Next Up"
        case .recentlyAdded: "Recently Added"
        }
    }
}

extension HomeHub.Kind: Hashable {}

@Observable
@MainActor
final class HomeModel {
    enum State: Equatable {
        case loading
        case loaded([HomeHub])
        case failed(String)
    }

    private(set) var state = State.loading
    /// Set when the server refused the token, so the app should return to sign-in.
    private(set) var sessionExpired = false

    private let client: any JellyfinClient
    private let limit: Int

    init(client: any JellyfinClient, limit: Int = 24) {
        self.client = client
        self.limit = limit
    }

    /// Loads the hubs and refreshes them quietly when some are already showing. One failing hub
    /// doesn't hide the others, and the whole screen fails only when nothing could load.
    func load() async {
        if case .failed = state {
            state = .loading
        }
        let client = client
        let limit = limit
        async let resume = Self.outcome { try await client.resumeItems(limit: limit) }
        async let nextUp = Self.outcome { try await client.nextUp(limit: limit) }
        async let latest = Self.outcome { try await client.latestItems(libraryID: nil, limit: limit) }
        let outcomes = await [
            (HomeHub.Kind.continueWatching, resume),
            (HomeHub.Kind.nextUp, nextUp),
            (HomeHub.Kind.recentlyAdded, latest),
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
        state = .loaded(outcomes.compactMap { kind, outcome in
            guard case .success(let items) = outcome, !items.isEmpty else { return nil }
            return HomeHub(kind: kind, items: items)
        })
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
}
