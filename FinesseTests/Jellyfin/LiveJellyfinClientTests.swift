import Foundation
import Testing
@testable import FinEsse

@Suite(.serialized) struct LiveJellyfinClientTests {
    private let serverURL = URL(string: "http://jellyfin.invalid:8096")!
    private let device = DeviceIdentity(
        clientName: "Finesse",
        clientVersion: "1.0",
        deviceName: "Test",
        deviceID: "fixture-device"
    )

    private func makeClient() -> LiveJellyfinClient {
        LiveJellyfinClient(serverURL: serverURL, device: device) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            return configuration
        }
    }

    private func signedInClient() async -> LiveJellyfinClient {
        let client = makeClient()
        await client.setSession(UserSession(
            serverURL: serverURL,
            serverID: "fixture-server",
            user: User(id: "user-id", name: "finesse-test"),
            accessToken: "FIXTURE_TOKEN"
        ))
        return client
    }

    /// Serves `fixture` for every request.
    private func serve(_ fixture: String, status: Int = 200) throws {
        let body = try Fixture.data(fixture)
        StubURLProtocol.reset { _ in .response(status: status, body: body) }
    }

    private func serve(status: Int, body: String = "") {
        let data = Data(body.utf8)
        StubURLProtocol.reset { _ in .response(status: status, body: data) }
    }

    /// The query exactly as it goes out. `lastQuery` decodes it, which would hide a wrong encoding.
    private func wireQuery() throws -> String {
        try #require(StubURLProtocol.recorded.last?.request.url?.query(percentEncoded: true))
    }

    private func lastQuery() throws -> [String: String] {
        let request = try #require(StubURLProtocol.recorded.last?.request)
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        return Dictionary(
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { "\($0),\($1)" }
        )
    }

    private func lastBody() throws -> [String: Any] {
        let body = try #require(StubURLProtocol.recorded.last?.body)
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    // MARK: Server and sign-in

    @Test func stopTranscodingNamesThisDeviceAndThePlaySession() async throws {
        StubURLProtocol.reset { _ in .response(status: 204, body: Data()) }
        let client = await signedInClient()

        try await client.stopTranscoding(playSessionID: "old-session")

        let request = try #require(StubURLProtocol.recorded.last?.request)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path() == "/Videos/ActiveEncodings")
        let query = try lastQuery()
        #expect(query["deviceId"] == "fixture-device")
        #expect(query["playSessionId"] == "old-session")
    }

    @Test func readsServerInfo() async throws {
        try serve("system-info-public")
        let info = try await makeClient().serverInfo()
        #expect(info.id == "fixture-server")
        #expect(info.version == "12.4.0")
    }

    @Test func htmlResponseIsNotAJellyfinServer() async {
        serve(status: 200, body: "<html></html>")
        await #expect(throws: JellyfinError.notAJellyfinServer) {
            _ = try await makeClient().serverInfo()
        }
    }

    @Test func missingEndpointIsNotAJellyfinServer() async {
        serve(status: 404)
        await #expect(throws: JellyfinError.notAJellyfinServer) {
            _ = try await makeClient().serverInfo()
        }
    }

    @Test func decodesPublicUsers() async throws {
        try serve("users-public")
        let users = try await makeClient().publicUsers()
        #expect(users.map(\.name) == ["User 1", "User 2"])
    }

    @Test func signInStoresSessionAndSendsToken() async throws {
        try serve("authenticate")
        let client = makeClient()
        let session = try await client.signIn(username: "finesse-test", password: "secret")
        #expect(session.accessToken == "FIXTURE_TOKEN")
        #expect(session.serverID == "fixture-server")
        #expect(session.serverURL == serverURL)
        #expect(await client.currentSession() == session)

        let signInHeader = try #require(StubURLProtocol.recorded.last?.request.value(forHTTPHeaderField: "Authorization"))
        #expect(signInHeader.hasPrefix("MediaBrowser "))
        #expect(signInHeader.contains("DeviceId=fixture-device"))
        #expect(signInHeader.contains("Client=Finesse"))
        #expect(!signInHeader.contains("Token="))
        let body = try lastBody()
        #expect(body["Username"] as? String == "finesse-test")
        #expect(body["Pw"] as? String == "secret")

        try serve("user-views")
        _ = try await client.libraries()
        let header = try #require(StubURLProtocol.recorded.last?.request.value(forHTTPHeaderField: "Authorization"))
        #expect(header.contains("Token=FIXTURE_TOKEN"))
    }

    @Test(arguments: [
        ("Lounge, TV", "Lounge TV"),
        ("Josh's Apple TV", "Josh's Apple TV"),
        ("Caf\u{e9} \"TV\"=1", "Caf TV1"),
        (",,,", "Apple TV"),
    ])
    func deviceNameIsSafeInHeader(name: String, expected: String) {
        #expect(LiveJellyfinClient.headerSafe(name) == expected)
    }

    @Test func wrongPasswordIsInvalidCredentials() async {
        serve(status: 401)
        await #expect(throws: JellyfinError.invalidCredentials) {
            _ = try await makeClient().signIn(username: "finesse-test", password: "wrong")
        }
    }

    @Test func expiredTokenIsNotSignedIn() async {
        serve(status: 401)
        let client = await signedInClient()
        await #expect(throws: JellyfinError.notSignedIn) {
            _ = try await client.libraries()
        }
    }

    @Test func signOutPostsLogoutAndClearsSession() async throws {
        serve(status: 204)
        let client = await signedInClient()
        try await client.signOut()
        let request = try #require(StubURLProtocol.recorded.last?.request)
        #expect(request.url?.path() == "/Sessions/Logout")
        #expect(request.httpMethod == "POST")
        #expect(await client.currentSession() == nil)
    }

    @Test func callsWithoutSessionMakeNoRequest() async {
        serve(status: 200)
        await #expect(throws: JellyfinError.notSignedIn) {
            _ = try await makeClient().resumeItems(limit: 5)
        }
        #expect(StubURLProtocol.recorded.isEmpty)
    }

    // MARK: Quick Connect

    @Test func quickConnectFlow() async throws {
        serve(status: 200, body: "true")
        let client = makeClient()
        #expect(try await client.isQuickConnectEnabled())

        try serve("quickconnect-initiate")
        let request = try await client.startQuickConnect()
        #expect(request.code == "123456")
        #expect(!request.isAuthenticated)

        try serve("quickconnect-status")
        _ = try await client.quickConnectStatus(request)
        #expect(try lastQuery()["secret"] == "FIXTURE_SECRET")

        try serve("authenticate")
        _ = try await client.signIn(quickConnect: request)
        #expect(try lastBody()["Secret"] as? String == "FIXTURE_SECRET")
        #expect(await client.currentSession() != nil)
    }

    @Test func quickConnectInitiateRefusedMeansDisabled() async {
        serve(status: 401)
        await #expect(throws: JellyfinError.quickConnectDisabled) {
            _ = try await makeClient().startQuickConnect()
        }
    }

    // MARK: Home

    @Test func emptyHubsDecode() async throws {
        let client = await signedInClient()
        try serve("resume")
        #expect(try await client.resumeItems(limit: 5).isEmpty)
        try serve("nextup")
        #expect(try await client.nextUp(limit: 5).isEmpty)
    }

    @Test func resumeItemCarriesPosition() async throws {
        try serve("resume-with-item")
        let items = try await signedInClient().resumeItems(limit: 5)
        let item = try #require(items.first)
        #expect(item.kind == .episode)
        #expect(item.userState.playbackPosition > .zero)
        #expect(item.seriesID != nil)
        let query = try lastQuery()
        #expect(query["limit"] == "5")
        #expect(query["userId"] == "user-id")
    }

    @Test func latestDecodesBareArray() async throws {
        try serve("latest")
        let items = try await signedInClient().latestItems(libraryID: nil, limit: 4)
        #expect(!items.isEmpty)
    }

    // MARK: Browsing

    @Test func mapsLibraryKinds() async throws {
        try serve("user-views")
        let libraries = try await signedInClient().libraries()
        #expect(libraries.map(\.kind) == [.movies, .shows])
    }

    @Test func sendsItemQueryAndReturnsPage() async throws {
        try serve("items-movies")
        var query = ItemQuery(libraryID: "library", kinds: [.movie], sort: .dateAdded, direction: .descending)
        query.filter = ItemFilter(isPlayed: false, isFavorite: true, genres: ["Drama"], years: [1999])
        query.startIndex = 0
        query.limit = 3
        let page = try await signedInClient().items(query)
        #expect(page.totalCount == 1265)
        #expect(page.items.count == 2)
        #expect(page.hasMore)

        let sent = try lastQuery()
        #expect(sent["parentId"] == "library")
        #expect(sent["includeItemTypes"] == "Movie")
        #expect(sent["recursive"] == "true")
        #expect(sent["sortBy"] == "DateCreated,SortName")
        #expect(sent["sortOrder"] == "Descending")
        #expect(sent["filters"] == "IsUnplayed")
        #expect(sent["isFavorite"] == "true")
        #expect(sent["genres"] == "Drama")
        #expect(sent["years"] == "1999")
        #expect(sent["limit"] == "3")
        #expect(sent["startIndex"] == "0")
    }

    @Test func searchSendsTermAndKinds() async throws {
        try serve("items-search")
        let items = try await signedInClient().search(term: "the", kinds: [.movie, .series, .episode], limit: 4)
        #expect(!items.isEmpty)
        let sent = try lastQuery()
        #expect(sent["searchTerm"] == "the")
        #expect(sent["includeItemTypes"] == "Movie,Series,Episode")
    }

    /// The legacy endpoint has the years and ratings, and only the newer one has languages.
    private func serveFilters() throws {
        let legacy = try Fixture.data("filters")
        let newer = Data(#"{"Genres":[{"Name":"Drama","Id":"genre"}],"Tags":[],"AudioLanguages":[{"Name":"English (eng)","Value":"eng"},{"Name":"Spanish; Castilian (spa)","Value":"spa"}],"SubtitleLanguages":[{"Name":"French (fre)","Value":"fre"}]}"#.utf8)
        StubURLProtocol.reset { request in
            .response(status: 200, body: request.url?.path.hasSuffix("/Items/Filters2") == true ? newer : legacy)
        }
    }

    @Test func decodesFilterOptions() async throws {
        try serveFilters()
        let options = try await signedInClient().filterOptions(libraryID: "library", kinds: [.movie])
        #expect(!options.genres.isEmpty)
        #expect(!options.years.isEmpty)
        #expect(!options.officialRatings.isEmpty)
        #expect(!options.tags.isEmpty)
        #expect(options.audioLanguages.map(\.id) == ["eng", "spa"])
        #expect(options.audioLanguages.map(\.name) == ["English", "Spanish; Castilian"])
        #expect(options.subtitleLanguages.map(\.name) == ["French"])
        #expect(try lastQuery()["parentId"] == "library")
    }

    @Test func sendsEveryFilter() async throws {
        try serve("items-movies")
        var filter = ItemFilter()
        filter.isResumable = true
        filter.tags = ["one", "two"]
        filter.officialRatings = ["AU-MA 15+"]
        filter.studios = [FilterValue(id: "s1", name: "A"), FilterValue(id: "s2", name: "B")]
        filter.audioLanguages = [FilterValue(id: "eng", name: "English")]
        filter.subtitleLanguages = [FilterValue(id: "fre", name: "French")]
        filter.hasSubtitles = true
        filter.hasTrailer = true
        filter.hasSpecialFeature = true
        filter.hasThemeSong = true
        filter.hasThemeVideo = true
        filter.is3D = true
        filter.is4K = true
        filter.isHD = false
        filter.videoTypes = [.bluRay, .dvd]
        filter.seriesStatuses = [.continuing, .ended]
        filter.minCommunityRating = 7
        filter.name = .letter("M")
        _ = try await signedInClient().items(ItemQuery(kinds: [.series], sort: .dateEpisodeAdded, filter: filter))

        let sent = try lastQuery()
        #expect(sent["sortBy"] == "DateLastContentAdded,SortName")
        #expect(sent["filters"] == "IsResumable")
        #expect(sent["tags"] == "one,two")
        #expect(try wireQuery().contains("officialRatings=AU-MA%2015%2B"))
        #expect(sent["studioIds"] == "s1,s2")
        #expect(sent["audioLanguages"] == "eng")
        #expect(sent["subtitleLanguages"] == "fre")
        for name in ["hasSubtitles", "hasTrailer", "hasSpecialFeature", "hasThemeSong", "hasThemeVideo", "is3D", "is4K"] {
            #expect(sent[name] == "true", "\(name)")
        }
        #expect(sent["isHd"] == "false")
        #expect(sent["videoTypes"] == "BluRay,Dvd")
        #expect(sent["seriesStatus"] == "Continuing,Ended")
        #expect(sent["minCommunityRating"] == "7.0")
        #expect(sent["nameStartsWith"] == "M")
        #expect(sent["nameLessThan"] == nil)
    }

    /// Only true is ever sent, because some of the false forms are broken on the server.
    @Test func sendsNoFilterThatIsOff() async throws {
        try serve("items-movies")
        _ = try await signedInClient().items(ItemQuery(kinds: [.movie]))
        let sent = try lastQuery()
        for name in ["filters", "tags", "studioIds", "hasSubtitles", "is3D", "is4K", "isHd", "videoTypes", "seriesStatus", "minCommunityRating", "nameStartsWith", "nameLessThan"] {
            #expect(sent[name] == nil, "\(name)")
        }
    }

    @Test func digitsAndSymbolsAreEverythingBeforeA() async throws {
        try serve("items-movies")
        var filter = ItemFilter()
        filter.name = .beforeA
        _ = try await signedInClient().items(ItemQuery(kinds: [.movie], filter: filter))
        let sent = try lastQuery()
        #expect(sent["nameLessThan"] == "A")
        #expect(sent["nameStartsWith"] == nil)
    }

    /// A server reads a bare plus as a space, so ratings like AU-MA 15+ would match nothing.
    @Test func aPlusIsEscapedInEveryValueOfEveryQuery() async throws {
        try serve("items-movies")
        var filter = ItemFilter()
        filter.genres = ["Drama+Comedy"]
        filter.tags = ["C++"]
        filter.officialRatings = ["R18+"]
        filter.name = .letter("+")
        filter.studios = [FilterValue(id: "a+b", name: "Studio")]
        filter.audioLanguages = [FilterValue(id: "x+y", name: "Language")]
        let client = await signedInClient()
        _ = try await client.items(ItemQuery(libraryID: "lib+1", searchTerm: "1+1", filter: filter))
        let wire = try wireQuery()
        #expect(!wire.contains("+"), "Sent \(wire)")
        for expected in ["genres=Drama%2BComedy", "tags=C%2B%2B", "officialRatings=R18%2B", "nameStartsWith=%2B", "studioIds=a%2Bb", "audioLanguages=x%2By", "searchTerm=1%2B1", "parentId=lib%2B1"] {
            #expect(wire.contains(expected), "\(expected) in \(wire)")
        }

        try serve("filters")
        _ = try? await client.search(term: "a+b", kinds: [.movie], limit: 3)
        #expect(!(try wireQuery().contains("+")))
    }

    @Test func imageURLsEscapeAPlusToo() async throws {
        let client = await signedInClient()
        let url = client.imageURL(itemID: "item", kind: .primary, tag: "a+b", index: nil, maxWidth: nil)
        #expect(url?.query(percentEncoded: true)?.contains("tag=a%2Bb") == true)
    }

    @Test func itemIDsComeFromEveryPageAndAskForLittle() async throws {
        func page(_ ids: [Int], total: Int) -> Data {
            let items = ids.map { #"{"Id":"\#($0)"}"# }.joined(separator: ",")
            return Data(#"{"Items":[\#(items)],"TotalRecordCount":\#(total),"StartIndex":0}"#.utf8)
        }
        let first = page(Array(0..<1000), total: 1002)
        let second = page([1000, 1001], total: 1002)
        StubURLProtocol.reset { request in
            .response(status: 200, body: request.url?.query?.contains("startIndex=1000") == true ? second : first)
        }
        var filter = ItemFilter()
        filter.genres = ["Drama"]
        let ids = try await signedInClient().itemIDs(ItemQuery(kinds: [.movie], filter: filter))
        #expect(ids.count == 1002)
        let sent = try lastQuery()
        #expect(sent["genres"] == "Drama")
        #expect(sent["enableImages"] == "false")
        #expect(sent["enableUserData"] == "false")
    }

    @Test func aQueryCanAskForParticularItems() async throws {
        try serve("items-movies")
        _ = try await signedInClient().items(ItemQuery(ids: ["a", "b"], limit: 2))
        #expect(try lastQuery()["ids"] == "a,b")
    }

    @Test func anOrdinarySpaceStaysASpace() async throws {
        try serve("items-movies")
        var filter = ItemFilter()
        filter.officialRatings = ["AU-MA 15"]
        _ = try await signedInClient().items(ItemQuery(filter: filter))
        #expect(try wireQuery().contains("officialRatings=AU-MA%2015"))
    }

    private func studioPage(_ ids: [String?], total: Int) -> Data {
        let items = ids.map { id in id.map { #"{"Id":"\#($0)","Name":"Studio \#($0)"}"# } ?? #"{"Name":"No ID"}"# }
        return Data(#"{"Items":[\#(items.joined(separator: ","))],"TotalRecordCount":\#(total),"StartIndex":0}"#.utf8)
    }

    /// A row with no ID is dropped, but the next page still starts after it.
    @Test func studioPagingCountsTheRowsReceived() async throws {
        let first = studioPage([nil] + (1..<500).map(String.init), total: 502)
        let second = studioPage(["500", "501"], total: 502)
        StubURLProtocol.reset { request in
            .response(status: 200, body: request.url?.query?.contains("startIndex=500") == true ? second : first)
        }
        let studios = try await signedInClient().studios(libraryID: "library", kinds: [.movie])
        #expect(studios.count == 501)
        #expect(Set(studios.map(\.id)).count == 501)
    }

    /// Fails its request rather than hanging if paging never ends.
    @Test func studioPagingCantLoopForever() async throws {
        let body = studioPage(Array(repeating: nil, count: 500), total: 100_000)
        StubURLProtocol.reset { _ in
            StubURLProtocol.recorded.count > 400 ? .response(status: 500, body: Data()) : .response(status: 200, body: body)
        }
        _ = try await signedInClient().studios(libraryID: "library", kinds: [.movie])
        #expect(StubURLProtocol.recorded.count <= 2, "A page with nothing usable should end it")
    }

    @Test func aServerThatRepeatsItsFirstPageStillEnds() async throws {
        let body = studioPage((0..<500).map(String.init), total: 100_000)
        StubURLProtocol.reset { _ in
            StubURLProtocol.recorded.count > 400 ? .response(status: 500, body: Data()) : .response(status: 200, body: body)
        }
        let studios = try await signedInClient().studios(libraryID: "library", kinds: [.movie])
        #expect(studios.count == 500)
        #expect(StubURLProtocol.recorded.count <= 2, "A page with nothing new should end it")
    }

    @Test func fetchesEveryPageOfStudios() async throws {
        func page(_ ids: [String], total: Int) -> Data {
            let items = ids.map { #"{"Id":"\#($0)","Name":"Studio \#($0)"}"# }.joined(separator: ",")
            return Data(#"{"Items":[\#(items)],"TotalRecordCount":\#(total),"StartIndex":0}"#.utf8)
        }
        let first = page((0..<500).map(String.init), total: 502)
        let second = page(["500", "501"], total: 502)
        StubURLProtocol.reset { request in
            .response(status: 200, body: request.url?.query?.contains("startIndex=500") == true ? second : first)
        }
        let studios = try await signedInClient().studios(libraryID: "library", kinds: [.movie])
        #expect(studios.count == 502)
        #expect(studios.last == FilterValue(id: "501", name: "Studio 501"))
        #expect(try lastQuery()["includeItemTypes"] == "Movie")
    }

    // MARK: Detail

    @Test func mapsMovieDetail() async throws {
        try serve("item-movie")
        let item = try await signedInClient().item(id: "movie")
        #expect(item.kind == .movie)
        #expect(!item.name.isEmpty)
        #expect(item.runTime != nil)
        #expect(!item.people.isEmpty)
        #expect(item.images.primaryTag != nil)
    }

    @Test func mapsSeriesDetail() async throws {
        try serve("item-series")
        let item = try await signedInClient().item(id: "series")
        #expect(item.kind == .series)
        #expect(item.childCount == 2)
    }

    @Test func mapsEpisodeDetail() async throws {
        try serve("item-episode")
        let item = try await signedInClient().item(id: "episode")
        #expect(item.kind == .episode)
        #expect(item.seriesID != nil)
        #expect(item.seasonID != nil)
        #expect(item.parentIndexNumber == 1)
        #expect(item.indexNumber == 1)
    }

    @Test func listsSeasonsAndEpisodes() async throws {
        let client = await signedInClient()
        try serve("seasons")
        #expect(try await client.seasons(seriesID: "series").allSatisfy { $0.kind == .season })
        try serve("episodes")
        let episodes = try await client.episodes(seriesID: "series", seasonID: "season")
        #expect(episodes.allSatisfy { $0.kind == .episode })
        #expect(try lastQuery()["seasonId"] == "season")
    }

    @Test func updatesUserState() async throws {
        try serve("user-data")
        let client = await signedInClient()
        let state = try await client.setPlayed(false, itemID: "item")
        #expect(!state.isPlayed)
        #expect(state.playbackPosition == .zero)
        #expect(StubURLProtocol.recorded.last?.request.httpMethod == "DELETE")
        #expect(StubURLProtocol.recorded.last?.request.url?.path() == "/UserPlayedItems/item")

        _ = try await client.setFavorite(true, itemID: "item")
        #expect(StubURLProtocol.recorded.last?.request.httpMethod == "POST")
        #expect(StubURLProtocol.recorded.last?.request.url?.path() == "/UserFavoriteItems/item")
    }

    // MARK: Images

    @Test func imageURLNeedsTag() {
        #expect(makeClient().imageURL(itemID: "item", kind: .primary, tag: nil, index: nil, maxWidth: nil) == nil)
    }

    @Test func imageURLKeepsServerPathAndParameters() throws {
        let client = LiveJellyfinClient(
            serverURL: URL(string: "https://media.example.com/jellyfin")!,
            device: device
        )
        let url = try #require(client.imageURL(itemID: "item", kind: .backdrop, tag: "abc", index: 1, maxWidth: 400))
        #expect(url.absoluteString == "https://media.example.com/jellyfin/Items/item/Images/Backdrop/1?tag=abc&maxWidth=400")
    }

    // MARK: Playback

    private func playbackRequest() -> PlaybackInfoRequest {
        PlaybackInfoRequest(
            itemID: "movie",
            startPosition: Ticks(seconds: 10),
            deviceProfile: DeviceProfile(
                directPlayProfiles: [DirectPlayProfile(type: .video, container: "mp4", videoCodec: "h264", audioCodec: "aac")]
            )
        )
    }

    @Test func playbackInfoSendsProfileAndResolvesURLs() async throws {
        try serve("playback-info")
        let info = try await signedInClient().playbackInfo(playbackRequest())
        #expect(info.playSessionID == "fixture-play-session")
        let source = try #require(info.mediaSources.first)
        #expect(source.supportsTranscoding)
        #expect(source.directPlayURL == nil)
        let transcoding = try #require(source.transcodingURL)
        #expect(transcoding.absoluteString.hasPrefix("http://jellyfin.invalid:8096/"))
        #expect(transcoding.query()?.contains("ApiKey=FIXTURE_TOKEN") == true)
        #expect(source.streams.contains { $0.kind == .video })
        #expect(source.streams.contains { $0.kind == .subtitle && $0.deliveryURL?.host() == "jellyfin.invalid" })

        let body = try lastBody()
        #expect(body["UserId"] as? String == "user-id")
        #expect(body["StartTimeTicks"] as? Int == 100_000_000)
        let profile = try #require(body["DeviceProfile"] as? [String: Any])
        let direct = try #require((profile["DirectPlayProfiles"] as? [[String: Any]])?.first)
        #expect(direct["Container"] as? String == "mp4")
        #expect(direct["Type"] as? String == "Video")
    }

    @Test func directPlaySourceGetsStaticStreamURL() async throws {
        var json = try Fixture.json("playback-info")
        var sources = try #require(json["MediaSources"] as? [[String: Any]])
        sources[0]["SupportsDirectPlay"] = true
        json["MediaSources"] = sources
        let body = try JSONSerialization.data(withJSONObject: json)
        StubURLProtocol.reset { _ in .response(status: 200, body: body) }

        let info = try await signedInClient().playbackInfo(playbackRequest())
        let url = try #require(info.mediaSources.first?.directPlayURL)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/Videos/movie/stream")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query["static"] == "true")
        #expect(query["ApiKey"] == "FIXTURE_TOKEN")
        #expect(query["playSessionId"] == "fixture-play-session")
        #expect(query["mediaSourceId"] == sources[0]["Id"] as? String)
    }

    @Test func mapsMediaSegments() async throws {
        serve(status: 200, body: """
        {"Items":[{"Id":"s1","ItemId":"e1","Type":"Intro","StartTicks":0,"EndTicks":900000000},
        {"Id":"s2","ItemId":"e1","Type":"Outro","StartTicks":1000000000,"EndTicks":1100000000}],
        "TotalRecordCount":2,"StartIndex":0}
        """)
        let segments = try await signedInClient().mediaSegments(itemID: "e1")
        #expect(segments.map(\.kind) == [.intro, .outro])
        #expect(segments[0].end.seconds == 90)
    }

    @Test func noSegmentsIsEmpty() async throws {
        let client = await signedInClient()
        try serve("segments")
        #expect(try await client.mediaSegments(itemID: "e1").isEmpty)
        serve(status: 404)
        #expect(try await client.mediaSegments(itemID: "e1").isEmpty)
    }

    @Test func reportsPlaybackToTheRightEndpoints() async throws {
        serve(status: 204)
        let client = await signedInClient()
        let report = PlaybackReport(
            itemID: "item",
            mediaSourceID: "source",
            playSessionID: "session",
            position: Ticks(seconds: 30),
            isPaused: true,
            playMethod: .directStream,
            audioStreamIndex: 1,
            subtitleStreamIndex: 2
        )

        try await client.reportPlaybackStart(report)
        #expect(StubURLProtocol.recorded.last?.request.url?.path() == "/Sessions/Playing")

        try await client.reportPlaybackProgress(report)
        #expect(StubURLProtocol.recorded.last?.request.url?.path() == "/Sessions/Playing/Progress")
        let progress = try lastBody()
        #expect(progress["ItemId"] as? String == "item")
        #expect(progress["MediaSourceId"] as? String == "source")
        #expect(progress["PlaySessionId"] as? String == "session")
        #expect(progress["PositionTicks"] as? Int == 300_000_000)
        #expect(progress["IsPaused"] as? Bool == true)
        #expect(progress["PlayMethod"] as? String == "DirectStream")
        #expect(progress["AudioStreamIndex"] as? Int == 1)
        #expect(progress["SubtitleStreamIndex"] as? Int == 2)

        try await client.reportPlaybackStopped(report)
        #expect(StubURLProtocol.recorded.last?.request.url?.path() == "/Sessions/Playing/Stopped")
        #expect(try lastBody()["PositionTicks"] as? Int == 300_000_000)
    }

    // MARK: Errors

    @Test(arguments: [
        (403, JellyfinError.forbidden),
        (404, JellyfinError.notFound),
        (500, JellyfinError.server(status: 500)),
    ])
    func mapsStatusCodes(status: Int, expected: JellyfinError) async {
        serve(status: status)
        let client = await signedInClient()
        await #expect(throws: expected) {
            _ = try await client.item(id: "item")
        }
    }

    @Test func networkErrorHidesURL() async {
        let secretURL = URL(string: "http://jellyfin.invalid/stream?ApiKey=FIXTURE_TOKEN")!
        let error = URLError(.timedOut, userInfo: [NSURLErrorFailingURLErrorKey: secretURL])
        guard case .network(let message) = LiveJellyfinClient.mapError(error) as? JellyfinError else {
            Issue.record("Expected a network error")
            return
        }
        #expect(!message.contains("FIXTURE_TOKEN"))
    }

    // MARK: Values the SDK's strict enums don't know

    /// A fixture with `edit` applied, as the server might send it after an upgrade.
    private func serveEdited(_ fixture: String, edit: (inout [String: Any]) -> Void) throws {
        var json = try #require(try JSONSerialization.jsonObject(with: Fixture.data(fixture)) as? [String: Any])
        edit(&json)
        let body = try JSONSerialization.data(withJSONObject: json)
        StubURLProtocol.reset { _ in .response(status: 200, body: body) }
    }

    private func editItem(_ index: Int, in json: inout [String: Any], edit: (inout [String: Any]) -> Void) {
        var items = json["Items"] as? [[String: Any]] ?? []
        edit(&items[index])
        json["Items"] = items
    }

    @Test func anUnknownItemTypeKeepsTheWholeListAndThatItem() async throws {
        let client = await signedInClient()
        try serveEdited("items-movies") { json in
            editItem(0, in: &json) { $0["Type"] = "SomeKindFromTheFuture" }
        }
        let page = try await client.items(ItemQuery(kinds: [.movie]))
        #expect(page.items.count >= 2)
        #expect(page.items[0].kind == .other(""))
        #expect(!page.items[0].name.isEmpty)
        #expect(page.items[1].kind == .movie)
    }

    @Test func anUnknownValueOnEveryItemIsFixedInOnePass() async throws {
        let client = await signedInClient()
        try serveEdited("items-movies") { json in
            let count = (json["Items"] as? [Any])?.count ?? 0
            for index in 0..<count {
                editItem(index, in: &json) { $0["VideoType"] = "SomethingNew" }
            }
        }
        let page = try await client.items(ItemQuery(kinds: [.movie]))
        #expect(page.items.allSatisfy { $0.kind == .movie })
    }

    @Test func anUnknownNestedValueKeepsTheItem() async throws {
        let client = await signedInClient()
        try serveEdited("items-movies") { json in
            editItem(0, in: &json) {
                $0["MediaStreams"] = [["Type": "Video", "VideoRangeType": "HDR99", "Index": 0]]
                var state = $0["UserData"] as? [String: Any] ?? [:]
                state["PlaybackPositionTicks"] = 50
                $0["UserData"] = state
            }
        }
        let original = try #require(try JSONSerialization.jsonObject(with: Fixture.data("items-movies")) as? [String: Any])
        let firstName = (original["Items"] as? [[String: Any]])?.first?["Name"] as? String
        let page = try await client.items(ItemQuery(kinds: [.movie]))
        #expect(page.items[0].name == firstName)
        #expect(page.items[0].kind == .movie)
        #expect(page.items[0].userState.playbackPosition == Ticks(rawValue: 50))
    }

    @Test func aNestedObjectMissingARequiredFieldCostsOnlyThatObject() async throws {
        let client = await signedInClient()
        let original = try #require(try JSONSerialization.jsonObject(with: Fixture.data("items-movies")) as? [String: Any])
        let count = (original["Items"] as? [Any])?.count
        let firstName = (original["Items"] as? [[String: Any]])?.first?["Name"] as? String
        try serveEdited("items-movies") { json in
            editItem(0, in: &json) { $0["UserData"] = ["Played": true] }
        }
        let page = try await client.items(ItemQuery(kinds: [.movie]))
        #expect(page.items.count == count)
        #expect(page.items[0].name == firstName)
    }

    /// The legacy filters endpoint returns nothing at all without a parent library.
    @Test func filterOptionsAreGatheredFromTheMatchingLibraries() async throws {
        let client = await signedInClient()
        let views = #"{"Items":[{"Id":"movies-id","Name":"Movies","CollectionType":"movies"},{"Id":"more-id","Name":"More","CollectionType":"movies"},{"Id":"tv-id","Name":"TV","CollectionType":"tvshows"}]}"#
        StubURLProtocol.reset { request in
            let url = request.url?.absoluteString ?? ""
            let body: String
            if url.contains("UserViews") {
                body = views
            } else if url.contains("movies-id") {
                body = #"{"Genres":["Drama","Action"],"Years":[2020],"OfficialRatings":["PG"]}"#
            } else if url.contains("more-id") {
                body = #"{"Genres":["Comedy","Action"],"Years":[1999],"OfficialRatings":["PG"]}"#
            } else if url.contains("tv-id") {
                body = #"{"Genres":["Reality"],"Years":[1],"OfficialRatings":["TV-MA"]}"#
            } else {
                body = #"{"Genres":[],"Years":[],"OfficialRatings":[]}"#
            }
            return .response(status: 200, body: Data(body.utf8))
        }
        let options = try await client.filterOptions(libraryID: nil, kinds: [.movie])
        #expect(options.genres == ["Action", "Comedy", "Drama"])
        #expect(options.years == [2020, 1999])
        #expect(options.officialRatings == ["PG"])
    }

    @Test func aWrongTypeInAnOptionalFieldKeepsTheItem() async throws {
        let client = await signedInClient()
        try serveEdited("items-movies") { json in
            editItem(0, in: &json) { $0["ProductionYear"] = "not a number" }
        }
        let page = try await client.items(ItemQuery(kinds: [.movie]))
        #expect(page.items[0].productionYear == nil)
        #expect(page.items[1].productionYear != nil)
    }

    @Test func aListEntryThatIsNotAnItemIsDropped() async throws {
        let client = await signedInClient()
        try serveEdited("items-movies") { json in
            var items = json["Items"] as? [Any] ?? []
            let count = items.count
            items[0] = "not an item"
            json["Items"] = items
            json["TotalRecordCount"] = count
        }
        let page = try await client.items(ItemQuery(kinds: [.movie]))
        #expect(!page.items.isEmpty)
        #expect(page.items.allSatisfy { !$0.name.isEmpty })
    }

    @Test func datesStillDecodeInARepairedResponse() async throws {
        let client = await signedInClient()
        try serveEdited("items-movies") { json in
            editItem(0, in: &json) {
                $0["VideoType"] = "SomethingNew"
                $0["PremiereDate"] = "2021-03-04T05:06:07.1234567Z"
            }
        }
        let page = try await client.items(ItemQuery(kinds: [.movie]))
        let parts = try #require(page.items[0].premiereDate).timeIntervalSince1970
        #expect(abs(parts - 1_614_834_367.123) < 0.01)
    }

    @Test func somethingThatIsNotJSONIsStillAnError() async throws {
        let client = await signedInClient()
        serve(status: 200, body: "<html>not json</html>")
        await #expect(throws: JellyfinError.self) {
            _ = try await client.items(ItemQuery(kinds: [.movie]))
        }
    }

    // MARK: Quick Connect and sign-out

    @Test func anExpiredQuickConnectSecretSaysSo() async throws {
        let client = makeClient()
        serve(status: 404)
        let request = QuickConnectRequest(code: "123456", secret: "gone", isAuthenticated: false)
        await #expect(throws: JellyfinError.quickConnectExpired) {
            _ = try await client.quickConnectStatus(request)
        }
    }

    /// The server can't be told, so the error is still reported, but this client holds no session.
    @Test func signingOutOfflineStillClearsTheSession() async throws {
        let client = await signedInClient()
        StubURLProtocol.reset { _ in .failure(URLError(.notConnectedToInternet)) }
        await #expect(throws: JellyfinError.self) {
            try await client.signOut()
        }
        #expect(await client.currentSession() == nil)
    }
}
