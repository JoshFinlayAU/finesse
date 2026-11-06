import Foundation
import Observation

extension MediaItem {
    /// A series or season has no single thing to play, so it plays one of its episodes instead.
    var isPlayable: Bool {
        kind == .movie || kind == .episode
    }

    /// The line under the title: year or episode number, runtime and ratings.
    var detailMetadata: [String] {
        var parts: [String] = []
        if kind == .episode {
            if let season = parentIndexNumber, let episode = indexNumber {
                parts.append("S\(season) E\(episode)")
            }
            if let seasonlessEpisode = parentIndexNumber == nil ? indexNumber : nil {
                parts.append("E\(seasonlessEpisode)")
            }
        }
        if let productionYear {
            parts.append(String(productionYear))
        }
        if let runTime, let formatted = Self.runTimeText(runTime) {
            parts.append(formatted)
        }
        if let officialRating {
            parts.append(officialRating)
        }
        if let communityRating {
            parts.append("\u{2605} \(communityRating.formatted(.number.precision(.fractionLength(1))))")
        }
        if let criticRating {
            parts.append("\(Int(criticRating.rounded()))% critics")
        }
        return parts
    }

    static func runTimeText(_ runTime: Ticks) -> String? {
        let minutes = Int((runTime.seconds / 60).rounded())
        guard minutes > 0 else { return nil }
        let hours = minutes / 60
        if hours == 0 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m"
    }
}

/// One movie, show, season or episode page, and the items that hang off it.
@Observable
@MainActor
final class DetailModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase = Phase.loading
    private(set) var item: MediaItem
    private(set) var seasons: [MediaItem] = []
    private(set) var episodes: [MediaItem] = []
    private(set) var similar: [MediaItem] = []
    /// What Play starts. For a show or season, this is the next episode to watch.
    private(set) var playTarget: MediaItem?
    /// A failed Mark Watched or Favourite, shown once and then cleared.
    var actionError: String?
    /// Set when the server refused the token, so the app should return to sign-in.
    private(set) var sessionExpired = false

    private enum Action {
        case watched
        case favorite
    }

    private let client: any JellyfinClient
    private let similarLimit: Int
    private var loadGeneration = 0
    /// A second press while the first is out would send the same value again, not undo it.
    private var actionsInFlight: Set<Action> = []

    init(item: MediaItem, client: any JellyfinClient, similarLimit: Int = 18) {
        self.item = item
        self.client = client
        self.similarLimit = similarLimit
    }

    var playTitle: String {
        guard let playTarget else { return "Play" }
        let verb = playTarget.resumePosition == nil ? "Play" : "Resume"
        guard item.kind != playTarget.kind,
              let season = playTarget.parentIndexNumber,
              let episode = playTarget.indexNumber
        else { return verb }
        return "\(verb) S\(season) E\(episode)"
    }

    /// Other episodes in this season, for an episode's page.
    var otherEpisodes: [MediaItem] {
        episodes.filter { $0.id != item.id }
    }

    /// Loads the page, and updates it quietly if it is already showing. Only the item itself can
    /// fail the page. A row that can't load stays as it was, or hidden if it never loaded. A newer
    /// load replaces an older one still running, so a slow answer can't undo a fresh one.
    func load() async {
        if case .failed = phase {
            phase = .loading
        }
        loadGeneration += 1
        let current = loadGeneration
        do {
            let loaded = try await client.item(id: item.id)
            guard isCurrent(current) else { return }
            item = loaded
            await loadRelated(current)
            guard isCurrent(current) else { return }
            phase = .loaded
        } catch {
            guard !(error is CancellationError), current == loadGeneration else { return }
            if error.isSessionExpired {
                sessionExpired = true
            } else if phase != .loaded {
                phase = .failed(error.userMessage)
            }
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == loadGeneration && !Task.isCancelled
    }

    func toggleWatched() async {
        guard actionsInFlight.insert(.watched).inserted else { return }
        defer { actionsInFlight.remove(.watched) }
        await change { client, id, state in
            try await client.setPlayed(!state.isPlayed, itemID: id)
        }
        // Marking a show or season also changes its episodes, and so what Play should start.
        await load()
    }

    func toggleFavorite() async {
        guard actionsInFlight.insert(.favorite).inserted else { return }
        defer { actionsInFlight.remove(.favorite) }
        await change { client, id, state in
            try await client.setFavorite(!state.isFavorite, itemID: id)
        }
    }

    private func change(
        _ update: @Sendable (any JellyfinClient, String, UserItemState) async throws -> UserItemState
    ) async {
        do {
            item.userState = try await update(client, item.id, item.userState)
        } catch {
            if error.isSessionExpired {
                sessionExpired = true
            } else {
                actionError = error.userMessage
            }
        }
    }

    private func loadRelated(_ current: Int) async {
        switch item.kind {
        case .movie:
            if let loaded = await optional({ try await $0.similarItems(id: $1.id, limit: self.similarLimit) }), isCurrent(current) {
                similar = loaded
            }
            playTarget = item
        case .series:
            if let loaded = await optional({ try await $0.seasons(seriesID: $1.id) }), isCurrent(current) {
                seasons = loaded
            }
            if let loaded = await optional({ try await $0.similarItems(id: $1.id, limit: self.similarLimit) }), isCurrent(current) {
                similar = loaded
            }
            if let target = await seriesPlayTarget(), isCurrent(current) {
                playTarget = target
            }
        case .season:
            if let seriesID = item.seriesID,
               let loaded = await optional({ client, item in try await client.episodes(seriesID: seriesID, seasonID: item.id) }),
               isCurrent(current) {
                episodes = loaded
                playTarget = Self.nextEpisode(in: loaded)
            }
        case .episode:
            if let seriesID = item.seriesID, let seasonID = item.seasonID,
               let loaded = await optional({ client, _ in try await client.episodes(seriesID: seriesID, seasonID: seasonID) }),
               isCurrent(current) {
                episodes = loaded
            }
            playTarget = item
        case .other:
            playTarget = nil
        }
    }

    /// The outer nil means it couldn't be worked out, so what's showing should stay. The inner nil
    /// means the show has nothing to play.
    private func seriesPlayTarget() async -> MediaItem?? {
        if let next = await optional({ client, item in try await client.nextUp(seriesID: item.id) }) ?? nil {
            return next
        }
        // Next Up is empty when everything has been watched, so offer the show from the start.
        guard let all = await optional({ client, item in try await client.episodes(seriesID: item.id, seasonID: nil) }) else {
            return nil
        }
        return .some(Self.nextEpisode(in: all))
    }

    /// The first episode started and not finished, else the first unwatched, else the first.
    static func nextEpisode(in episodes: [MediaItem]) -> MediaItem? {
        episodes.first { $0.resumePosition != nil && !$0.userState.isPlayed }
            ?? episodes.first { !$0.userState.isPlayed }
            ?? episodes.first
    }

    private func optional<T: Sendable>(
        _ load: @Sendable (any JellyfinClient, MediaItem) async throws -> T
    ) async -> T? {
        do {
            return try await load(client, item)
        } catch {
            if error.isSessionExpired {
                sessionExpired = true
            }
            return nil
        }
    }
}
