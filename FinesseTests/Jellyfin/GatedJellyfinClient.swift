import Foundation
@testable import FinEsse

/// Forwards to an `InMemoryJellyfinClient`, and can hold or fail named calls, so a test can decide
/// what finishes first. Named calls are "items@<startIndex>", "item", "setPlayed", "setFavorite",
/// "seasons", "episodes", "similar" and "nextUp".
actor GatedJellyfinClient: JellyfinClient {
    nonisolated let serverURL: URL
    let base: InMemoryJellyfinClient

    private var holdNext: Set<String> = []
    private var waiting: [String: CheckedContinuation<Void, Never>] = [:]
    private var failing: Set<String> = []
    private(set) var calls: [String: Int] = [:]

    init(base: InMemoryJellyfinClient) {
        self.base = base
        serverURL = base.serverURL
    }

    func hold(_ name: String) { holdNext.insert(name) }
    func fail(_ names: Set<String>) { failing = names }

    func isWaiting(_ name: String) -> Bool { waiting[name] != nil }

    func release(_ name: String) {
        waiting.removeValue(forKey: name)?.resume()
    }

    private func gate(_ name: String) async throws {
        calls[name, default: 0] += 1
        if holdNext.remove(name) != nil {
            await withCheckedContinuation { waiting[name] = $0 }
        }
        try Task.checkCancellation()
        if failing.contains(name) { throw JellyfinError.network("Failed by the test") }
    }

    func serverInfo() async throws -> ServerInfo { try await base.serverInfo() }
    func publicUsers() async throws -> [PublicUser] { try await base.publicUsers() }
    func signIn(username: String, password: String) async throws -> UserSession {
        try await base.signIn(username: username, password: password)
    }
    func isQuickConnectEnabled() async throws -> Bool { try await base.isQuickConnectEnabled() }
    func startQuickConnect() async throws -> QuickConnectRequest { try await base.startQuickConnect() }
    func quickConnectStatus(_ request: QuickConnectRequest) async throws -> QuickConnectRequest {
        try await base.quickConnectStatus(request)
    }
    func signIn(quickConnect request: QuickConnectRequest) async throws -> UserSession {
        try await base.signIn(quickConnect: request)
    }
    func setSession(_ session: UserSession?) async { await base.setSession(session) }
    func currentSession() async -> UserSession? { await base.currentSession() }
    func signOut() async throws { try await base.signOut() }
    func resumeItems(limit: Int) async throws -> [MediaItem] { try await base.resumeItems(limit: limit) }
    func nextUp(limit: Int) async throws -> [MediaItem] { try await base.nextUp(limit: limit) }
    func latestItems(libraryID: String?, limit: Int) async throws -> [MediaItem] {
        try await base.latestItems(libraryID: libraryID, limit: limit)
    }
    func libraries() async throws -> [Library] { try await base.libraries() }
    func items(_ query: ItemQuery) async throws -> Page<MediaItem> {
        // Read before the gate, so a held response carries what the server said when it was asked.
        let page = try await base.items(query)
        try await gate("items@\(query.startIndex)")
        return page
    }
    func filterOptions(libraryID: String?, kinds: [ItemKind]) async throws -> FilterOptions {
        try await base.filterOptions(libraryID: libraryID, kinds: kinds)
    }
    func search(term: String, kinds: [ItemKind], limit: Int) async throws -> [MediaItem] {
        try await base.search(term: term, kinds: kinds, limit: limit)
    }
    func item(id: String) async throws -> MediaItem {
        let item = try await base.item(id: id)
        try await gate("item")
        return item
    }
    func seasons(seriesID: String) async throws -> [MediaItem] {
        try await gate("seasons")
        return try await base.seasons(seriesID: seriesID)
    }
    func episodes(seriesID: String, seasonID: String?) async throws -> [MediaItem] {
        try await gate("episodes")
        return try await base.episodes(seriesID: seriesID, seasonID: seasonID)
    }
    func nextUp(seriesID: String) async throws -> MediaItem? {
        try await gate("nextUp")
        return try await base.nextUp(seriesID: seriesID)
    }
    func similarItems(id: String, limit: Int) async throws -> [MediaItem] {
        try await gate("similar")
        return try await base.similarItems(id: id, limit: limit)
    }
    func setPlayed(_ played: Bool, itemID: String) async throws -> UserItemState {
        try await gate("setPlayed")
        return try await base.setPlayed(played, itemID: itemID)
    }
    func setFavorite(_ favorite: Bool, itemID: String) async throws -> UserItemState {
        try await gate("setFavorite")
        return try await base.setFavorite(favorite, itemID: itemID)
    }
    nonisolated func imageURL(itemID: String, kind: ImageKind, tag: String?, index: Int?, maxWidth: Int?) -> URL? {
        base.imageURL(itemID: itemID, kind: kind, tag: tag, index: index, maxWidth: maxWidth)
    }
    func playbackInfo(_ request: PlaybackInfoRequest) async throws -> PlaybackInfo { try await base.playbackInfo(request) }
    func mediaSegments(itemID: String) async throws -> [MediaSegment] { try await base.mediaSegments(itemID: itemID) }
    func reportPlaybackStart(_ report: PlaybackReport) async throws { try await base.reportPlaybackStart(report) }
    func reportPlaybackProgress(_ report: PlaybackReport) async throws { try await base.reportPlaybackProgress(report) }
    func stopTranscoding(playSessionID: String) async throws {
        try await base.stopTranscoding(playSessionID: playSessionID)
    }

    func chapters(itemID: String) async throws -> [ItemChapter] { try await base.chapters(itemID: itemID) }
    func reportPlaybackStart(_ report: PlaybackReport) async throws { try await base.reportPlaybackStart(report) }
    func reportPlaybackProgress(_ report: PlaybackReport) async throws { try await base.reportPlaybackProgress(report) }
    func stopTranscoding(playSessionID: String) async throws {
        try await base.stopTranscoding(playSessionID: playSessionID)
    }

    func reportPlaybackStopped(_ report: PlaybackReport) async throws { try await base.reportPlaybackStopped(report) }

    /// Returns once a held call has arrived at its gate.
    func waitUntilWaiting(_ name: String) async {
        for _ in 0..<10_000 {
            if waiting[name] != nil { return }
            await Task.yield()
        }
    }
}
