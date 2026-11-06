import Foundation
import Get
import JellyfinAPI

/// `JellyfinClient` backed by the official SDK. Holds one SDK client at a time, rebuilt when the session changes.
actor LiveJellyfinClient: JellyfinClient {
    nonisolated let serverURL: URL
    private let device: DeviceIdentity
    private let makeSessionConfiguration: @Sendable () -> URLSessionConfiguration
    private var sdk: JellyfinAPI.JellyfinClient
    private var session: UserSession?

    init(
        serverURL: URL,
        device: DeviceIdentity,
        makeSessionConfiguration: @escaping @Sendable () -> URLSessionConfiguration = { .default }
    ) {
        self.serverURL = serverURL
        self.device = device
        self.makeSessionConfiguration = makeSessionConfiguration
        self.sdk = Self.makeSDK(
            serverURL: serverURL,
            device: device,
            accessToken: nil,
            sessionConfiguration: makeSessionConfiguration()
        )
    }

    private static func makeSDK(
        serverURL: URL,
        device: DeviceIdentity,
        accessToken: String?,
        sessionConfiguration: URLSessionConfiguration
    ) -> JellyfinAPI.JellyfinClient {
        JellyfinAPI.JellyfinClient(
            configuration: .init(
                url: serverURL,
                accessToken: accessToken,
                client: device.clientName,
                deviceName: headerSafe(device.deviceName),
                deviceID: device.deviceID,
                version: device.clientVersion
            ),
            sessionConfiguration: sessionConfiguration
        )
    }

    /// The SDK writes header fields unquoted and comma separated, and a device name is user-chosen.
    /// Keep only what survives that, or a name like "Lounge, TV" corrupts the header.
    static func headerSafe(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_.'"))
        let kept = name.unicodeScalars.filter { $0.isASCII && allowed.contains($0) }
        let safe = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        return safe.isEmpty ? "Apple TV" : safe
    }

    // MARK: Server and sign-in

    func serverInfo() async throws -> ServerInfo {
        do {
            let info = try await send(Paths.getPublicSystemInfo)
            guard let id = info.id, let version = info.version else { throw JellyfinError.notAJellyfinServer }
            return ServerInfo(id: id, name: info.serverName ?? "", version: version)
        } catch JellyfinError.decoding, JellyfinError.notFound {
            throw JellyfinError.notAJellyfinServer
        }
    }

    func publicUsers() async throws -> [PublicUser] {
        try await send(Paths.getPublicUsers).compactMap { user in
            guard let id = user.id, let name = user.name else { return nil }
            return PublicUser(
                id: id,
                name: name,
                hasPassword: user.hasConfiguredPassword ?? true,
                primaryImageTag: user.primaryImageTag
            )
        }
    }

    func signIn(username: String, password: String) async throws -> UserSession {
        let body = AuthenticateUserByName(pw: password, username: username)
        return try await signIn(with: Paths.authenticateUserByName(body))
    }

    func isQuickConnectEnabled() async throws -> Bool {
        let data = try await send(Paths.getQuickConnectEnabled)
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }

    func startQuickConnect() async throws -> QuickConnectRequest {
        do {
            return try QuickConnectRequest(await send(Paths.initiateQuickConnect))
        } catch JellyfinError.notSignedIn {
            throw JellyfinError.quickConnectDisabled
        }
    }

    func quickConnectStatus(_ request: QuickConnectRequest) async throws -> QuickConnectRequest {
        try QuickConnectRequest(await send(Paths.getQuickConnectState(secret: request.secret)))
    }

    func signIn(quickConnect request: QuickConnectRequest) async throws -> UserSession {
        try await signIn(with: Paths.authenticateWithQuickConnect(QuickConnectDto(secret: request.secret)))
    }

    private func signIn(with request: Request<AuthenticationResult>) async throws -> UserSession {
        let result: AuthenticationResult
        do {
            result = try await send(request)
        } catch JellyfinError.notSignedIn {
            throw JellyfinError.invalidCredentials
        }
        guard let token = result.accessToken, let user = result.user, let userID = user.id else {
            throw JellyfinError.decoding("Authentication response had no token or user")
        }
        let new = UserSession(
            serverURL: serverURL,
            serverID: result.serverID ?? "",
            user: User(id: userID, name: user.name ?? "", primaryImageTag: user.primaryImageTag),
            accessToken: token
        )
        await setSession(new)
        return new
    }

    // MARK: Session

    func setSession(_ session: UserSession?) async {
        self.session = session
        sdk = Self.makeSDK(
            serverURL: serverURL,
            device: device,
            accessToken: session?.accessToken,
            sessionConfiguration: makeSessionConfiguration()
        )
    }

    func currentSession() async -> UserSession? {
        session
    }

    func signOut() async throws {
        if session != nil {
            try await sendVoid(Paths.reportSessionEnded)
        }
        await setSession(nil)
    }

    // MARK: Home

    func resumeItems(limit: Int) async throws -> [MediaItem] {
        var parameters = Paths.GetResumeItemsParameters()
        parameters.userID = try userID()
        parameters.limit = limit
        parameters.enableUserData = true
        parameters.mediaTypes = [.video]
        return try await send(Paths.getResumeItems(parameters: parameters)).mediaItems
    }

    func nextUp(limit: Int) async throws -> [MediaItem] {
        var parameters = Paths.GetNextUpParameters()
        parameters.userID = try userID()
        parameters.limit = limit
        parameters.enableUserData = true
        return try await send(Paths.getNextUp(parameters: parameters)).mediaItems
    }

    func latestItems(libraryID: String?, limit: Int) async throws -> [MediaItem] {
        var parameters = Paths.GetLatestMediaParameters()
        parameters.userID = try userID()
        parameters.parentID = libraryID
        parameters.limit = limit
        parameters.enableUserData = true
        return try await send(Paths.getLatestMedia(parameters: parameters)).map(MediaItem.init)
    }

    // MARK: Browsing

    func libraries() async throws -> [Library] {
        var parameters = Paths.GetUserViewsParameters()
        parameters.userID = try userID()
        return try await send(Paths.getUserViews(parameters: parameters)).items?.map(Library.init) ?? []
    }

    func items(_ query: ItemQuery) async throws -> Page<MediaItem> {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = try userID()
        parameters.parentID = query.libraryID
        parameters.isRecursive = query.recursive
        parameters.startIndex = query.startIndex
        parameters.limit = query.limit
        parameters.enableUserData = true
        parameters.enableTotalRecordCount = true
        parameters.searchTerm = query.searchTerm
        parameters.includeItemTypes = query.kinds.isEmpty ? nil : query.kinds.compactMap(\.sdkKind)
        parameters.sortBy = [ItemSortBy(rawValue: query.sort.rawValue), .sortName].compactMap { $0 }
        parameters.sortOrder = [query.direction == .ascending ? .ascending : .descending]
        parameters.filters = query.filter.sdkFilters
        parameters.isFavorite = query.filter.isFavorite
        parameters.genres = query.filter.genres.isEmpty ? nil : query.filter.genres
        parameters.years = query.filter.years.isEmpty ? nil : query.filter.years
        parameters.officialRatings = query.filter.officialRatings.isEmpty ? nil : query.filter.officialRatings

        let result = try await send(Paths.getItems(parameters: parameters))
        let items = result.mediaItems
        return Page(
            items: items,
            startIndex: result.startIndex ?? query.startIndex,
            totalCount: result.totalRecordCount ?? query.startIndex + items.count
        )
    }

    func filterOptions(libraryID: String?, kinds: [ItemKind]) async throws -> FilterOptions {
        var parameters = Paths.GetQueryFiltersLegacyParameters()
        parameters.userID = try userID()
        parameters.parentID = libraryID
        parameters.includeItemTypes = kinds.isEmpty ? nil : kinds.compactMap(\.sdkKind)
        let result = try await send(Paths.getQueryFiltersLegacy(parameters: parameters))
        return FilterOptions(
            genres: result.genres ?? [],
            years: result.years ?? [],
            officialRatings: result.officialRatings ?? []
        )
    }

    func search(term: String, kinds: [ItemKind], limit: Int) async throws -> [MediaItem] {
        try await items(ItemQuery(kinds: kinds, searchTerm: term, limit: limit)).items
    }

    // MARK: Detail

    func item(id: String) async throws -> MediaItem {
        try await MediaItem(send(Paths.getItem(itemID: id, userID: userID())))
    }

    func seasons(seriesID: String) async throws -> [MediaItem] {
        var parameters = Paths.GetSeasonsParameters()
        parameters.userID = try userID()
        parameters.enableUserData = true
        return try await send(Paths.getSeasons(seriesID: seriesID, parameters: parameters)).mediaItems
    }

    func episodes(seriesID: String, seasonID: String?) async throws -> [MediaItem] {
        var parameters = Paths.GetEpisodesParameters()
        parameters.userID = try userID()
        parameters.seasonID = seasonID
        parameters.enableUserData = true
        parameters.fields = [.overview]
        return try await send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters)).mediaItems
    }

    func nextUp(seriesID: String) async throws -> MediaItem? {
        var parameters = Paths.GetNextUpParameters()
        parameters.userID = try userID()
        parameters.seriesID = seriesID
        parameters.limit = 1
        parameters.enableUserData = true
        return try await send(Paths.getNextUp(parameters: parameters)).mediaItems.first
    }

    func similarItems(id: String, limit: Int) async throws -> [MediaItem] {
        var parameters = Paths.GetSimilarItemsParameters()
        parameters.userID = try userID()
        parameters.limit = limit
        return try await send(Paths.getSimilarItems(itemID: id, parameters: parameters)).mediaItems
    }

    func setPlayed(_ played: Bool, itemID: String) async throws -> UserItemState {
        let userID = try userID()
        let request = played
            ? Paths.markPlayedItem(itemID: itemID, userID: userID)
            : Paths.markUnplayedItem(itemID: itemID, userID: userID)
        return try await UserItemState(send(request))
    }

    func setFavorite(_ favorite: Bool, itemID: String) async throws -> UserItemState {
        let userID = try userID()
        let request = favorite
            ? Paths.markFavoriteItem(itemID: itemID, userID: userID)
            : Paths.unmarkFavoriteItem(itemID: itemID, userID: userID)
        return try await UserItemState(send(request))
    }

    // MARK: Images

    nonisolated func imageURL(
        itemID: String,
        kind: ImageKind,
        tag: String?,
        index: Int?,
        maxWidth: Int?
    ) -> URL? {
        guard let tag else { return nil }
        var path = "Items/\(itemID)/Images/\(kind.rawValue)"
        if let index {
            path += "/\(index)"
        }
        var queryItems = [URLQueryItem(name: "tag", value: tag)]
        if let maxWidth {
            queryItems.append(URLQueryItem(name: "maxWidth", value: String(maxWidth)))
        }
        return serverURL.appending(path: path).appending(queryItems: queryItems)
    }

    // MARK: Playback

    func playbackInfo(_ request: PlaybackInfoRequest) async throws -> PlaybackInfo {
        let body = try PlaybackInfoDto(
            audioStreamIndex: request.audioStreamIndex,
            deviceProfile: JellyfinAPI.DeviceProfile(request.deviceProfile),
            enableDirectPlay: request.enableDirectPlay,
            enableDirectStream: request.enableDirectStream,
            enableTranscoding: request.enableTranscoding,
            maxStreamingBitrate: request.maxStreamingBitrate,
            mediaSourceID: request.mediaSourceID,
            startTimeTicks: request.startPosition.map { Int($0.rawValue) },
            subtitleStreamIndex: request.subtitleStreamIndex,
            userID: userID()
        )
        let response = try await send(Paths.getPostedPlaybackInfo(itemID: request.itemID, body))
        return PlaybackInfo(
            playSessionID: response.playSessionID,
            mediaSources: response.mediaSources?.map {
                mediaSource($0, itemID: request.itemID, playSessionID: response.playSessionID)
            } ?? [],
            errorCode: response.errorCode?.rawValue
        )
    }

    private func mediaSource(_ dto: MediaSourceInfo, itemID: String, playSessionID: String?) -> PlaybackMediaSource {
        let resolve: (String?) -> URL? = { [sdk] path in
            guard let path, !path.isEmpty else { return nil }
            return sdk.url(path: path)
        }
        var directPlayURL: URL?
        if dto.isSupportsDirectPlay == true || dto.isSupportsDirectStream == true {
            var parameters = Paths.GetVideoStreamParameters()
            parameters.isStatic = true
            parameters.mediaSourceID = dto.id
            parameters.playSessionID = playSessionID
            parameters.tag = dto.eTag
            directPlayURL = sdk.url(with: Paths.getVideoStream(itemID: itemID, parameters: parameters), queryAPIKey: true)
        }
        return PlaybackMediaSource(
            id: dto.id ?? "",
            name: dto.name,
            container: dto.container,
            size: dto.size.map(Int64.init),
            bitRate: dto.bitrate,
            runTime: Ticks(dto.runTimeTicks),
            supportsDirectPlay: dto.isSupportsDirectPlay ?? false,
            supportsDirectStream: dto.isSupportsDirectStream ?? false,
            supportsTranscoding: dto.isSupportsTranscoding ?? false,
            directPlayURL: directPlayURL,
            transcodingURL: resolve(dto.transcodingURL),
            transcodingSubProtocol: dto.transcodingSubProtocol?.rawValue,
            eTag: dto.eTag,
            liveStreamID: dto.liveStreamID,
            defaultAudioStreamIndex: dto.defaultAudioStreamIndex,
            defaultSubtitleStreamIndex: dto.defaultSubtitleStreamIndex,
            streams: dto.mediaStreams?.map { MediaStreamInfo($0, resolve: resolve) } ?? []
        )
    }

    func mediaSegments(itemID: String) async throws -> [MediaSegment] {
        _ = try userID()
        do {
            return try await send(Paths.getItemSegments(itemID: itemID)).items?.compactMap(MediaSegment.init) ?? []
        } catch JellyfinError.notFound {
            return []
        }
    }

    func reportPlaybackStart(_ report: PlaybackReport) async throws {
        _ = try userID()
        try await sendVoid(Paths.reportPlaybackStart(PlaybackStateInfo(report)))
    }

    func reportPlaybackProgress(_ report: PlaybackReport) async throws {
        _ = try userID()
        try await sendVoid(Paths.reportPlaybackProgress(PlaybackStateInfo(report)))
    }

    func reportPlaybackStopped(_ report: PlaybackReport) async throws {
        _ = try userID()
        let info = PlaybackStopInfo(
            itemID: report.itemID,
            liveStreamID: report.liveStreamID,
            mediaSourceID: report.mediaSourceID,
            playSessionID: report.playSessionID,
            positionTicks: Int(report.position.rawValue)
        )
        try await sendVoid(Paths.reportPlaybackStopped(info))
    }

    // MARK: Transport

    private func userID() throws -> String {
        guard let session else { throw JellyfinError.notSignedIn }
        return session.user.id
    }

    private func send<T: Decodable & Sendable>(_ request: Request<T>) async throws -> T {
        do {
            return try await sdk.send(request).value
        } catch {
            throw Self.mapError(error)
        }
    }

    private func sendVoid(_ request: Request<Void>) async throws {
        do {
            try await sdk.send(request)
        } catch {
            throw Self.mapError(error)
        }
    }

    /// Never includes a URL, because stream URLs and some requests carry the token.
    static func mapError(_ error: Error) -> Error {
        switch error {
        case is CancellationError, is JellyfinError:
            return error
        case APIError.unacceptableStatusCode(let status):
            switch status {
            case 401: return JellyfinError.notSignedIn
            case 403: return JellyfinError.forbidden
            case 404: return JellyfinError.notFound
            default: return JellyfinError.server(status: status)
            }
        case let urlError as URLError:
            switch urlError.code {
            case .cancelled: return CancellationError()
            case .appTransportSecurityRequiresSecureConnection: return JellyfinError.insecureConnectionBlocked
            default: return JellyfinError.network("URL error \(urlError.code.rawValue)")
            }
        case is DecodingError:
            return JellyfinError.decoding(String(describing: error))
        default:
            return JellyfinError.network(String(describing: type(of: error)))
        }
    }
}

private extension BaseItemDtoQueryResult {
    var mediaItems: [MediaItem] {
        items?.map(MediaItem.init) ?? []
    }
}

private extension QuickConnectRequest {
    init(_ dto: QuickConnectResult) throws {
        guard let code = dto.code, let secret = dto.secret else {
            throw JellyfinError.decoding("Quick Connect response had no code or secret")
        }
        self.init(code: code, secret: secret, isAuthenticated: dto.isAuthenticated ?? false)
    }
}

private extension ItemFilter {
    var sdkFilters: [JellyfinAPI.ItemFilter]? {
        var filters: [JellyfinAPI.ItemFilter] = []
        if let isPlayed {
            filters.append(isPlayed ? .isPlayed : .isUnplayed)
        }
        if isResumable == true {
            filters.append(.isResumable)
        }
        return filters.isEmpty ? nil : filters
    }
}
