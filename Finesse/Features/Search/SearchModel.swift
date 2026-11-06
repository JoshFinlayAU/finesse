import Foundation
import Observation

struct SearchGroup: Identifiable, Equatable {
    let kind: ItemKind
    let items: [MediaItem]

    var id: String { title }

    var title: String {
        switch kind {
        case .movie: "Movies"
        case .series: "TV Shows"
        case .episode: "Episodes"
        default: "Other"
        }
    }
}

@Observable
@MainActor
final class SearchModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded([SearchGroup])
        case failed(String)
    }

    private(set) var state = State.idle
    /// Set when the server refused the token, so the app should return to sign-in.
    private(set) var sessionExpired = false

    private let client: any JellyfinClient
    private let debounce: Duration
    private let limit: Int

    init(client: any JellyfinClient, debounce: Duration = .milliseconds(350), limit: Int = 24) {
        self.client = client
        self.debounce = debounce
        self.limit = limit
    }

    /// Run from `.task(id: text)`, so a new keystroke cancels this call during the debounce or the
    /// fetch and its stale results never show. Each kind gets its own query, because a single query
    /// over all kinds lets episodes crowd out movies and shows.
    func search(_ text: String) async {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            state = .idle
            return
        }
        do {
            try await Task.sleep(for: debounce)
        } catch {
            return
        }
        if case .loaded = state {
            // Keep the previous results on screen until the new ones arrive.
        } else {
            state = .loading
        }

        let client = client
        let limit = limit
        async let movies = Self.outcome { try await client.search(term: term, kinds: [.movie], limit: limit) }
        async let shows = Self.outcome { try await client.search(term: term, kinds: [.series], limit: limit) }
        async let episodes = Self.outcome { try await client.search(term: term, kinds: [.episode], limit: limit) }
        let outcomes = await [(ItemKind.movie, movies), (ItemKind.series, shows), (ItemKind.episode, episodes)]
        guard !Task.isCancelled else { return }

        let failures = outcomes.compactMap { outcome -> Error? in
            if case .failure(let error) = outcome.1 { return error }
            return nil
        }
        if failures.contains(where: \.isSessionExpired) {
            sessionExpired = true
        } else if failures.count == outcomes.count, let first = failures.first {
            state = .failed(first.userMessage)
        } else {
            state = .loaded(outcomes.compactMap { kind, outcome in
                guard case .success(let items) = outcome, !items.isEmpty else { return nil }
                return SearchGroup(kind: kind, items: items)
            })
        }
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
