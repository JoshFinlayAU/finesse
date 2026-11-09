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
    /// How long every request takes, to show what screens do on a slow server.
    var responseDelay: Duration?
    /// Hold these calls open, so a test can make something happen during them.
    var playbackInfoGate: (@Sendable () async -> Void)?
    var reportStartGate: (@Sendable () async -> Void)?
    var reportProgressGate: (@Sendable () async -> Void)?
    var reportStoppedGate: (@Sendable () async -> Void)?

    private(set) var startReports: [PlaybackReport] = []
    private(set) var progressReports: [PlaybackReport] = []
    private(set) var stopReports: [PlaybackReport] = []
    private(set) var stoppedTranscodes: [String] = []
    private(set) var playbackInfoRequests: [PlaybackInfoRequest] = []
    private(set) var itemQueries: [ItemQuery] = []

    private var session: UserSession?
    private var quickConnectPolls = 0
    /// Live connections that are open, newest last. `emit` sends to all of them.
    private var liveSockets: [FakeLiveSocket] = []
    /// Makes opening a live connection throw, to exercise reconnecting.
    var liveSocketFailure: JellyfinError?
    private(set) var liveSocketsOpened = 0

    init(serverURL: URL = URL(string: "http://fake.invalid:8096")!) {
        self.serverURL = serverURL
    }

    /// Runs `body` on the actor, for seeding several values at once.
    func configure(_ body: @Sendable (isolated InMemoryJellyfinClient) -> Void) {
        body(self)
    }

    // MARK: Server and sign-in

    func serverInfo() async throws -> ServerInfo {
        try await check()
        return serverInfoValue
    }

    func publicUsers() async throws -> [PublicUser] {
        try await check()
        return publicUsersValue
    }

    func signIn(username: String, password: String) async throws -> UserSession {
        try await check()
        guard credentials[username] == password else { throw JellyfinError.invalidCredentials }
        return makeSession(username: username)
    }

    func isQuickConnectEnabled() async throws -> Bool {
        try await check()
        return quickConnectEnabled
    }

    func startQuickConnect() async throws -> QuickConnectRequest {
        try await check()
        guard quickConnectEnabled else { throw JellyfinError.quickConnectDisabled }
        quickConnectPolls = 0
        return QuickConnectRequest(code: "123456", secret: "fake-secret", isAuthenticated: false)
    }

    func quickConnectStatus(_ request: QuickConnectRequest) async throws -> QuickConnectRequest {
        try await check()
        quickConnectPolls += 1
        var updated = request
        updated.isAuthenticated = quickConnectPolls >= quickConnectPollsUntilApproved
        return updated
    }

    func signIn(quickConnect request: QuickConnectRequest) async throws -> UserSession {
        try await check()
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
        try await check()
        session = nil
    }

    // MARK: Home

    func resumeItems(limit: Int) async throws -> [MediaItem] {
        try await checkSession()
        return Array(resumeValue.prefix(limit))
    }

    func nextUp(limit: Int) async throws -> [MediaItem] {
        try await checkSession()
        return Array(nextUpValue.prefix(limit))
    }

    func latestItems(libraryID: String?, limit: Int) async throws -> [MediaItem] {
        try await checkSession()
        return Array(latestValue.prefix(limit))
    }

    // MARK: Browsing

    func libraries() async throws -> [Library] {
        try await checkSession()
        return librariesValue
    }

    func items(_ query: ItemQuery) async throws -> Page<MediaItem> {
        try await checkSession()
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
            matches = matches.filter { $0.userState.playbackPosition > .zero }
        }
        if !query.ids.isEmpty {
            matches = matches.filter { query.ids.contains($0.id) }
        }
        if let extraFilterMatch {
            matches = matches.filter { extraFilterMatch($0, query.filter) }
        }
        matches = Self.sorted(matches, by: query.sort, query.direction)
        let page = matches.dropFirst(query.startIndex).prefix(query.limit)
        return Page(items: Array(page), startIndex: query.startIndex, totalCount: matches.count)
    }

    func itemIDs(_ query: ItemQuery) async throws -> [String] {
        var all = query
        all.startIndex = 0
        all.limit = .max
        return try await items(all).items.map(\.id)
    }

    func filterOptions(libraryID: String?, kinds: [ItemKind]) async throws -> FilterOptions {
        try await checkSession()
        return filterOptionsValue
    }

    func studios(libraryID: String?, kinds: [ItemKind]) async throws -> [FilterValue] {
        try await checkSession()
        return studiosValue
    }

    func search(term: String, kinds: [ItemKind], limit: Int) async throws -> [MediaItem] {
        let query = ItemQuery(kinds: kinds, searchTerm: term, limit: limit)
        return try await items(query).items
    }

    // MARK: Detail

    func item(id: String) async throws -> MediaItem {
        try await checkSession()
        guard let match = allItems.first(where: { $0.id == id }) else { throw JellyfinError.notFound }
        return match
    }

    func seasons(seriesID: String) async throws -> [MediaItem] {
        try await checkSession()
        return allItems.filter { $0.kind == .season && $0.seriesID == seriesID }
    }

    func episodes(seriesID: String, seasonID: String?) async throws -> [MediaItem] {
        try await checkSession()
        return allItems.filter {
            $0.kind == .episode && $0.seriesID == seriesID && (seasonID == nil || $0.seasonID == seasonID)
        }
    }

    func nextUp(seriesID: String) async throws -> MediaItem? {
        try await checkSession()
        return nextUpValue.first { $0.seriesID == seriesID }
    }

    func similarItems(id: String, limit: Int) async throws -> [MediaItem] {
        try await checkSession()
        return Array(allItems.filter { $0.id != id }.prefix(limit))
    }

    func setPlayed(_ played: Bool, itemID: String) async throws -> UserItemState {
        try await updateState(itemID: itemID) {
            $0.isPlayed = played
            $0.playbackPosition = .zero
        }
    }

    func setFavorite(_ favorite: Bool, itemID: String) async throws -> UserItemState {
        try await updateState(itemID: itemID) { $0.isFavorite = favorite }
    }

    private func updateState(itemID: String, _ change: (inout UserItemState) -> Void) async throws -> UserItemState {
        try await checkSession()
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
        try await checkSession()
        await playbackInfoGate?()
        playbackInfoRequests.append(request)
        return playbackInfoValue
    }

    func mediaSegments(itemID: String) async throws -> [MediaSegment] {
        try await checkSession()
        return segments[itemID] ?? []
    }

    func chapters(itemID: String) async throws -> [ItemChapter] {
        try await checkSession()
        return chapters[itemID] ?? []
    }

    func reportPlaybackStart(_ report: PlaybackReport) async throws {
        try await checkSession()
        await reportStartGate?()
        startReports.append(report)
    }

    func reportPlaybackProgress(_ report: PlaybackReport) async throws {
        try await checkSession()
        await reportProgressGate?()
        progressReports.append(report)
    }

    func stopTranscoding(playSessionID: String) async throws {
        try await checkSession()
        stoppedTranscodes.append(playSessionID)
    }

    func reportPlaybackStopped(_ report: PlaybackReport) async throws {
        try await checkSession()
        await reportStoppedGate?()
        stopReports.append(report)
    }

    // MARK: Checks

    private func check() async throws {
        if let responseDelay { try? await Task.sleep(for: responseDelay) }
        if let failure { throw failure }
    }

    private func checkSession() async throws {
        try await check()
        if session == nil { throw JellyfinError.notSignedIn }
    }
}

private extension InMemoryJellyfinClient {
    /// Follows the server: Random is a new order for every request, and with no direction. Sorts on
    /// something a seeded item doesn't hold, like Date Added or Bitrate, fall through to its name.
    static func sorted(_ items: [MediaItem], by sort: ItemSort, _ direction: SortDirection) -> [MediaItem] {
        if sort == .random {
            return items.shuffled()
        }
        func ordered<Value: Comparable>(_ key: (MediaItem) -> Value?) -> [MediaItem] {
            items.sorted { first, second in
                switch (key(first), key(second)) {
                case let (lhs?, rhs?) where lhs != rhs: lhs < rhs
                case (nil, _?): true
                case (_?, nil): false
                default: first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                }
            }
        }
        let ascending: [MediaItem] = switch sort {
        case .releaseDate: ordered(\.premiereDate)
        case .releaseYear: ordered(\.productionYear)
        case .communityRating: ordered(\.communityRating)
        case .criticRating: ordered(\.criticRating)
        case .parentalRating: ordered(\.officialRating)
        case .runTime: ordered { $0.runTime?.rawValue }
        case .favourites: ordered { $0.userState.isFavorite ? 1 : 0 }
        case .watched: ordered { $0.userState.isPlayed ? 1 : 0 }
        default: ordered { _ in Int?.none }
        }
        return direction == .descending ? ascending.reversed() : ascending
    }
}

// MARK: Live updates

extension InMemoryJellyfinClient: LiveEventSource {
    func openLiveSocket() async throws -> (socket: any LiveSocket, userID: String) {
        if let liveSocketFailure { throw liveSocketFailure }
        guard let session else { throw JellyfinError.notSignedIn }
        liveSocketsOpened += 1
        let socket = FakeLiveSocket()
        liveSockets.removeAll { $0.isClosed }
        liveSockets.append(socket)
        // Like the server, which asks for keep-alives as soon as a client connects.
        socket.deliver(#"{"MessageType":"ForceKeepAlive","Data":60}"#)
        return (socket, session.user.id)
    }

    /// Sends a message, in the server's own JSON, to every open live connection.
    func emit(_ message: String) {
        liveSockets.removeAll { $0.isClosed }
        for socket in liveSockets {
            socket.deliver(message)
        }
    }

    /// Ends every open live connection, as a server restart would.
    func dropLiveConnections() {
        for socket in liveSockets {
            socket.fail()
        }
        liveSockets.removeAll()
    }

    var openLiveSocketCount: Int {
        liveSockets.filter { !$0.isClosed }.count
    }

    var liveMessagesSent: [String] {
        liveSockets.flatMap(\.sent)
    }

    /// Adds an episode to a series as a library scan would, and says so on the live connection.
    func addEpisode(_ episode: MediaItem) {
        allItems.append(episode)
        latestValue.insert(episode, at: 0)
        var updated: [String] = []
        if let seriesID = episode.seriesID, let index = allItems.firstIndex(where: { $0.id == seriesID }) {
            allItems[index].userState.unplayedItemCount = (allItems[index].userState.unplayedItemCount ?? 0) + 1
            updated.append(seriesID)
        }
        let message: [String: Any] = [
            "MessageType": "LibraryChanged",
            "Data": [
                "ItemsAdded": [episode.id], "ItemsUpdated": updated, "ItemsRemoved": [String](),
                "FoldersAddedTo": [String](), "FoldersRemovedFrom": [String](), "CollectionFolders": [String](),
            ],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: message) {
            emit(String(decoding: data, as: UTF8.self))
        }
    }
}

/// A live connection inside the process. Messages queue until read, as on a real socket.
final class FakeLiveSocket: LiveSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [String] = []
    private var waiting: CheckedContinuation<String, Error>?
    private var closed = false
    private var sentMessages: [String] = []

    var isClosed: Bool { lock.withLock { closed } }
    var sent: [String] { lock.withLock { sentMessages } }

    func deliver(_ message: String) {
        let waiter: CheckedContinuation<String, Error>? = lock.withLock {
            guard !closed else { return nil }
            if let waiting {
                self.waiting = nil
                return waiting
            }
            queued.append(message)
            return nil
        }
        waiter?.resume(returning: message)
    }

    func fail() {
        let waiter: CheckedContinuation<String, Error>? = lock.withLock {
            closed = true
            defer { waiting = nil }
            return waiting
        }
        waiter?.resume(throwing: URLError(.networkConnectionLost))
    }

    func send(_ text: String) async throws {
        try lock.withLock {
            guard !closed else { throw URLError(.networkConnectionLost) }
            sentMessages.append(text)
        }
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let result: Result<String, Error>? = lock.withLock {
                if !queued.isEmpty { return .success(queued.removeFirst()) }
                if closed { return .failure(URLError(.networkConnectionLost)) }
                waiting = continuation
                return nil
            }
            if let result { continuation.resume(with: result) }
        }
    }

    func close() {
        fail()
    }
}

