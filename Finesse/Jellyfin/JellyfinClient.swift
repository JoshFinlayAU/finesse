import Foundation

/// Everything the app asks of a Jellyfin server. One instance talks to one server URL.
/// Views and engines depend on this protocol and the plain models, never on SDK types.
protocol JellyfinClient: AnyObject, Sendable {
    var serverURL: URL { get }

    // MARK: Server and sign-in (no session needed)

    func serverInfo() async throws -> ServerInfo
    func publicUsers() async throws -> [PublicUser]
    /// Signs in and makes the returned session current.
    func signIn(username: String, password: String) async throws -> UserSession
    func isQuickConnectEnabled() async throws -> Bool
    func startQuickConnect() async throws -> QuickConnectRequest
    func quickConnectStatus(_ request: QuickConnectRequest) async throws -> QuickConnectRequest
    /// Call once `quickConnectStatus` reports authenticated. Makes the returned session current.
    func signIn(quickConnect request: QuickConnectRequest) async throws -> UserSession

    // MARK: Session

    /// Switches to a stored session, or clears the current one with nil. Makes no network call.
    func setSession(_ session: UserSession?) async
    func currentSession() async -> UserSession?
    /// Revokes the current token on the server and clears the session.
    func signOut() async throws

    // MARK: Home

    func resumeItems(limit: Int) async throws -> [MediaItem]
    func nextUp(limit: Int) async throws -> [MediaItem]
    func latestItems(libraryID: String?, limit: Int) async throws -> [MediaItem]

    // MARK: Browsing

    func libraries() async throws -> [Library]
    func items(_ query: ItemQuery) async throws -> Page<MediaItem>
    func filterOptions(libraryID: String?, kinds: [ItemKind]) async throws -> FilterOptions
    func search(term: String, kinds: [ItemKind], limit: Int) async throws -> [MediaItem]

    // MARK: Detail

    func item(id: String) async throws -> MediaItem
    func seasons(seriesID: String) async throws -> [MediaItem]
    func episodes(seriesID: String, seasonID: String?) async throws -> [MediaItem]
    func nextUp(seriesID: String) async throws -> MediaItem?
    func similarItems(id: String, limit: Int) async throws -> [MediaItem]
    func setPlayed(_ played: Bool, itemID: String) async throws -> UserItemState
    func setFavorite(_ favorite: Bool, itemID: String) async throws -> UserItemState

    // MARK: Images

    /// Builds the URL only. Returns nil when `tag` is nil, so an item with no image makes no request.
    func imageURL(
        itemID: String,
        kind: ImageKind,
        tag: String?,
        index: Int?,
        maxWidth: Int?
    ) -> URL?

    // MARK: Playback

    func playbackInfo(_ request: PlaybackInfoRequest) async throws -> PlaybackInfo
    func mediaSegments(itemID: String) async throws -> [MediaSegment]
    func reportPlaybackStart(_ report: PlaybackReport) async throws
    func reportPlaybackProgress(_ report: PlaybackReport) async throws
    func reportPlaybackStopped(_ report: PlaybackReport) async throws
    /// Ends the server's transcode for a play session that is no longer in use.
    func stopTranscoding(playSessionID: String) async throws
}
