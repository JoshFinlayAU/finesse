import Foundation

/// A `JellyfinClient` with no network, for previews and unit tests. Seed the public vars,
/// or set `failure` to make every call throw.
actor InMemoryJellyfinClient: JellyfinClient {
    nonisolated let serverURL: URL

    var serverInfoValue = ServerInfo(id: "fake-server", name: "Fake Server", version: "12.4.0")
    var publicUsersValue: [PublicUser] = [
        PublicUser(id: "user-1", name: "Test User", hasPassword: true),
    ]
    /// Username to password. Signing in with anything else throws `invalidCredentials`.
    var credentials = ["Test User": "password"]
    var quickConnectEnabled = true
    /// Polls of `quickConnectStatus` before it reports authenticated.
    var quickConnectPollsUntilApproved = 1

    var resumeValue: [MediaItem] = []
    var nextUpValue: [MediaItem] = []
    var latestValue: [MediaItem] = []
    var librariesValue: [Library] = []
    var allItems: [MediaItem] = []
    var filterOptionsValue = FilterOptions()
    var studiosValue: [FilterValue] = []
    /// Tests that care about what a filter matches say so here, since a seeded item has no streams or tags.
    var extraFilterMatch: (@Sendable (MediaItem, ItemFilter) -> Bool)?
    var playbackInfoValue = PlaybackInfo()
    var segments: [String: [MediaSegment]] = [:]
    var chapters: [String: [ItemChapter]] = [:]
    var failure: JellyfinError?
    /// Hold these calls open, so a test can make something happen during them.
    var playbackInfoGate: (@Sendable () async -> Void)?
    var reportStartGate: (@Sendable () async -> Void)?
    var reportStoppedGate: (@Sendable () async -> Void)?

    private(set) var startReports: [PlaybackReport] = []
    private(set) var progressReports: [PlaybackReport] = []
    private(set) var stopReports: [PlaybackReport] = []
    private(set) var stoppedTranscodes: [String] = []
    private(set) var playbackInfoRequests: [PlaybackInfoRequest] = []
    private(set) var itemQueries: [ItemQuery] = []

    private var session: UserSession?
    private var quickConnectPolls = 0

    init(serverURL: URL = URL(string: "http://fake.invalid:8096")!) {
        self.serverURL = serverURL
    }

    /// Runs `body` on the actor, for seeding several values at once.
    func configure(_ body: @Sendable (isolated InMemoryJellyfinClient) -> Void) {
        body(self)
    }

    // MARK: Server and sign-in

    func serverInfo() async throws -> ServerInfo {
        try check()
        return serverInfoValue
    }

    func publicUsers() async throws -> [PublicUser] {
        try check()
        return publicUsersValue
    }

    func signIn(username: String, password: String) async throws -> UserSession {
        try check()
        guard credentials[username] == password else { throw JellyfinError.invalidCredentials }
        return makeSession(username: username)
    }

    func isQuickConnectEnabled() async throws -> Bool {
        try check()
        return quickConnectEnabled
    }

    func startQuickConnect() async throws -> QuickConnectRequest {
        try check()
        guard quickConnectEnabled else { throw JellyfinError.quickConnectDisabled }
        quickConnectPolls = 0
        return QuickConnectRequest(code: "123456", secret: "fake-secret", isAuthenticated: false)
    }

    func quickConnectStatus(_ request: QuickConnectRequest) async throws -> QuickConnectRequest {
        try check()
        quickConnectPolls += 1
        var updated = request
        updated.isAuthenticated = quickConnectPolls >= quickConnectPollsUntilApproved
        return updated
    }

    func signIn(quickConnect request: QuickConnectRequest) async throws -> UserSession {
        try check()
        guard request.isAuthenticated else { throw JellyfinError.invalidCredentials }
        return makeSession(username: publicUsersValue.first?.name ?? "Test User")
    }

    private func makeSession(username: String) -> UserSession {
        let id = publicUsersValue.first { $0.name == username }?.id ?? "user-1"
        let new = UserSession(
            serverURL: serverURL,
            serverID: serverInfoValue.id,
            user: User(id: id, name: username),
            accessToken: "fake-token"
        )
        session = new
        return new
    }

    // MARK: Session

    func setSession(_ session: UserSession?) async {
        self.session = session
    }

    func currentSession() async -> UserSession? {
        session
    }

    func signOut() async throws {
        try check()
        session = nil
    }

    // MARK: Home

    func resumeItems(limit: Int) async throws -> [MediaItem] {
        try checkSession()
        return Array(resumeValue.prefix(limit))
    }

    func nextUp(limit: Int) async throws -> [MediaItem] {
        try checkSession()
        return Array(nextUpValue.prefix(limit))
    }

    func latestItems(libraryID: String?, limit: Int) async throws -> [MediaItem] {
        try checkSession()
        return Array(latestValue.prefix(limit))
    }

    // MARK: Browsing

    func libraries() async throws -> [Library] {
        try checkSession()
        return librariesValue
    }

    func items(_ query: ItemQuery) async throws -> Page<MediaItem> {
        try checkSession()
        itemQueries.append(query)
        var matches = allItems
        if !query.kinds.isEmpty {
            matches = matches.filter { query.kinds.contains($0.kind) }
        }
        if let term = query.searchTerm, !term.isEmpty {
            matches = matches.filter { $0.name.localizedCaseInsensitiveContains(term) }
        }
        if let played = query.filter.isPlayed {
            matches = matches.filter { $0.userState.isPlayed == played }
        }
        if let favorite = query.filter.isFavorite {
            matches = matches.filter { $0.userState.isFavorite == favorite }
        }
        if !query.filter.genres.isEmpty {
            matches = matches.filter { !Set($0.genres).isDisjoint(with: query.filter.genres) }
        }
        if query.filter.isResumable == true {
            matches = matches.filter { $0.userState.playbackPosition != nil }
        }
        if let extraFilterMatch {
            matches = matches.filter { extraFilterMatch($0, query.filter) }
        }
        matches.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if query.direction == .descending {
            matches.reverse()
        }
        let page = matches.dropFirst(query.startIndex).prefix(query.limit)
        return Page(items: Array(page), startIndex: query.startIndex, totalCount: matches.count)
    }

    func filterOptions(libraryID: String?, kinds: [ItemKind]) async throws -> FilterOptions {
        try checkSession()
        return filterOptionsValue
    }

    func studios(libraryID: String?, kinds: [ItemKind]) async throws -> [FilterValue] {
        try checkSession()
        return studiosValue
    }

    func search(term: String, kinds: [ItemKind], limit: Int) async throws -> [MediaItem] {
        let query = ItemQuery(kinds: kinds, searchTerm: term, limit: limit)
        return try await items(query).items
    }

    // MARK: Detail

    func item(id: String) async throws -> MediaItem {
        try checkSession()
        guard let match = allItems.first(where: { $0.id == id }) else { throw JellyfinError.notFound }
        return match
    }

    func seasons(seriesID: String) async throws -> [MediaItem] {
        try checkSession()
        return allItems.filter { $0.kind == .season && $0.seriesID == seriesID }
    }

    func episodes(seriesID: String, seasonID: String?) async throws -> [MediaItem] {
        try checkSession()
        return allItems.filter {
            $0.kind == .episode && $0.seriesID == seriesID && (seasonID == nil || $0.seasonID == seasonID)
        }
    }

    func nextUp(seriesID: String) async throws -> MediaItem? {
        try checkSession()
        return nextUpValue.first { $0.seriesID == seriesID }
    }

    func similarItems(id: String, limit: Int) async throws -> [MediaItem] {
        try checkSession()
        return Array(allItems.filter { $0.id != id }.prefix(limit))
    }

    func setPlayed(_ played: Bool, itemID: String) async throws -> UserItemState {
        try updateState(itemID: itemID) {
            $0.isPlayed = played
            $0.playbackPosition = .zero
        }
    }

    func setFavorite(_ favorite: Bool, itemID: String) async throws -> UserItemState {
        try updateState(itemID: itemID) { $0.isFavorite = favorite }
    }

    private func updateState(itemID: String, _ change: (inout UserItemState) -> Void) throws -> UserItemState {
        try checkSession()
        guard let index = allItems.firstIndex(where: { $0.id == itemID }) else { throw JellyfinError.notFound }
        change(&allItems[index].userState)
        return allItems[index].userState
    }

    // MARK: Images

    nonisolated func imageURL(
        itemID: String,
        kind: ImageKind,
        tag: String?,
        index: Int?,
        maxWidth: Int?
    ) -> URL? {
        guard tag != nil else { return nil }
        return serverURL.appending(path: "Items/\(itemID)/Images/\(kind.rawValue)")
    }

    // MARK: Playback

    func playbackInfo(_ request: PlaybackInfoRequest) async throws -> PlaybackInfo {
        try checkSession()
        await playbackInfoGate?()
        playbackInfoRequests.append(request)
        return playbackInfoValue
    }

    func mediaSegments(itemID: String) async throws -> [MediaSegment] {
        try checkSession()
        return segments[itemID] ?? []
    }

    func chapters(itemID: String) async throws -> [ItemChapter] {
        try checkSession()
        return chapters[itemID] ?? []
    }

    func reportPlaybackStart(_ report: PlaybackReport) async throws {
        try checkSession()
        await reportStartGate?()
        startReports.append(report)
    }

    func reportPlaybackProgress(_ report: PlaybackReport) async throws {
        try checkSession()
        progressReports.append(report)
    }

    func stopTranscoding(playSessionID: String) async throws {
        try checkSession()
        stoppedTranscodes.append(playSessionID)
    }

    func reportPlaybackStopped(_ report: PlaybackReport) async throws {
        try checkSession()
        await reportStoppedGate?()
        stopReports.append(report)
    }

    // MARK: Checks

    private func check() throws {
        if let failure { throw failure }
    }

    private func checkSession() throws {
        try check()
        if session == nil { throw JellyfinError.notSignedIn }
    }
}
