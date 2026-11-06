import Foundation
import Testing
@testable import FinEsse

/// Runs as the test user against the server in `.env.local`. Tolerates any library contents and
/// restores any watch state it changes. Serialized because signing in again on one DeviceId
/// revokes the previous token.
private enum LiveServer {
    static let environment = ProcessInfo.processInfo.environment
    static let url = environment["JELLYFIN_URL"].flatMap(URL.init(string:))
    static let username = environment["JELLYFIN_USERNAME"]
    static let password = environment["JELLYFIN_PASSWORD"]
    static let isConfigured = url != nil && username != nil && password != nil

    static func makeClient() throws -> LiveJellyfinClient {
        LiveJellyfinClient(
            serverURL: try #require(url),
            device: DeviceIdentity(
                clientName: "Finesse Integration Tests",
                clientVersion: "1.0",
                deviceName: "Simulator",
                deviceID: "finesse-integration-tests"
            )
        )
    }

    static func signedInClient() async throws -> LiveJellyfinClient {
        let client = try makeClient()
        _ = try await client.signIn(username: try #require(username), password: try #require(password))
        return client
    }
}

@Suite(.serialized, .enabled(if: LiveServer.isConfigured, "JELLYFIN_* variables not set"))
struct LiveServerTests {
    private func firstItem(of kind: ItemKind, client: LiveJellyfinClient) async throws -> MediaItem? {
        try await client.items(ItemQuery(kinds: [kind], limit: 1)).items.first
    }

    @Test func serverInfoNeedsNoSession() async throws {
        let info = try await LiveServer.makeClient().serverInfo()
        #expect(!info.id.isEmpty)
        #expect(!info.version.isEmpty)
    }

    @Test func publicUsersDecode() async throws {
        _ = try await LiveServer.makeClient().publicUsers()
    }

    @Test func wrongPasswordIsRefused() async throws {
        let client = try LiveServer.makeClient()
        let username = try #require(LiveServer.username)
        await #expect(throws: JellyfinError.invalidCredentials) {
            _ = try await client.signIn(username: username, password: "not-the-password")
        }
    }

    @Test func signOutRevokesToken() async throws {
        let client = try await LiveServer.signedInClient()
        let session = try #require(await client.currentSession())
        _ = try await client.libraries()
        try await client.signOut()
        #expect(await client.currentSession() == nil)

        await client.setSession(session)
        await #expect(throws: JellyfinError.notSignedIn) {
            _ = try await client.libraries()
        }
    }

    @Test func signingInAgainOnSameDeviceRevokesOldToken() async throws {
        let client = try await LiveServer.signedInClient()
        let old = try #require(await client.currentSession())
        let newer = try await LiveServer.signedInClient()
        #expect(try await newer.currentSession()?.accessToken != old.accessToken)
        await #expect(throws: JellyfinError.notSignedIn) {
            _ = try await client.libraries()
        }
        try await newer.signOut()
    }

    @Test func quickConnectStartsWhenEnabled() async throws {
        let client = try LiveServer.makeClient()
        guard try await client.isQuickConnectEnabled() else { return }
        let request = try await client.startQuickConnect()
        #expect(!request.code.isEmpty)
        let status = try await client.quickConnectStatus(request)
        #expect(!status.isAuthenticated)
    }

    @Test func homeHubsDecode() async throws {
        let client = try await LiveServer.signedInClient()
        _ = try await client.resumeItems(limit: 10)
        _ = try await client.nextUp(limit: 10)
        _ = try await client.latestItems(libraryID: nil, limit: 10)
        try await client.signOut()
    }

    @Test func libraryPagesDoNotOverlap() async throws {
        let client = try await LiveServer.signedInClient()
        let libraries = try await client.libraries()
        #expect(!libraries.isEmpty)
        for library in libraries where library.kind == .movies || library.kind == .shows {
            let kind: ItemKind = library.kind == .movies ? .movie : .series
            let first = try await client.items(ItemQuery(libraryID: library.id, kinds: [kind], limit: 5))
            #expect(first.items.allSatisfy { $0.kind == kind })
            guard first.hasMore else { continue }
            let second = try await client.items(ItemQuery(libraryID: library.id, kinds: [kind], startIndex: 5, limit: 5))
            #expect(second.startIndex == 5)
            #expect(Set(first.items.map(\.id)).isDisjoint(with: second.items.map(\.id)))
        }
        try await client.signOut()
    }

    @Test func sortAndFiltersAreAccepted() async throws {
        let client = try await LiveServer.signedInClient()
        for sort in ItemSort.allCases {
            _ = try await client.items(ItemQuery(kinds: [.movie], sort: sort, direction: .descending, limit: 2))
        }
        let options = try await client.filterOptions(libraryID: nil, kinds: [.movie])
        if let genre = options.genres.first {
            var query = ItemQuery(kinds: [.movie], limit: 1)
            query.filter.genres = [genre]
            if let match = try await client.items(query).items.first {
                #expect(try await client.item(id: match.id).genres.contains(genre))
            }
        }
        if options.genres.count >= 2 {
            var one = ItemQuery(kinds: [.movie], limit: 1)
            one.filter.genres = [options.genres[0]]
            var both = one
            both.filter.genres = Array(options.genres.prefix(2))
            let oneCount = try await client.items(one).totalCount
            #expect(try await client.items(both).totalCount >= oneCount)
        }
        var unplayed = ItemQuery(kinds: [.movie], limit: 5)
        unplayed.filter.isPlayed = false
        #expect(try await client.items(unplayed).items.allSatisfy { !$0.userState.isPlayed })
        try await client.signOut()
    }

    @Test func searchFindsAKnownTitle() async throws {
        let client = try await LiveServer.signedInClient()
        guard let movie = try await firstItem(of: .movie, client: client),
              let word = movie.name.split(separator: " ").map(String.init).max(by: { $0.count < $1.count })
        else { return }
        let results = try await client.search(term: word, kinds: [.movie], limit: 100)
        #expect(results.contains { $0.id == movie.id })
        try await client.signOut()
    }

    @Test func movieDetailAndImage() async throws {
        let client = try await LiveServer.signedInClient()
        guard let listed = try await firstItem(of: .movie, client: client) else { return }
        let movie = try await client.item(id: listed.id)
        #expect(movie.kind == .movie)
        _ = try await client.similarItems(id: movie.id, limit: 3)
        if let url = client.imageURL(
            itemID: movie.id,
            kind: .primary,
            tag: movie.images.primaryTag,
            index: nil,
            maxWidth: 100
        ) {
            let (_, response) = try await URLSession.shared.data(from: url)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
        }
        try await client.signOut()
    }

    @Test func showHierarchy() async throws {
        let client = try await LiveServer.signedInClient()
        guard let show = try await firstItem(of: .series, client: client) else { return }
        #expect(try await client.item(id: show.id).kind == .series)
        let seasons = try await client.seasons(seriesID: show.id)
        guard let season = seasons.first else { return }
        #expect(season.kind == .season)
        let episodes = try await client.episodes(seriesID: show.id, seasonID: season.id)
        guard let episode = episodes.first else { return }
        let detail = try await client.item(id: episode.id)
        #expect(detail.kind == .episode)
        #expect(detail.seriesID == show.id)
        _ = try await client.nextUp(seriesID: show.id)
        #expect(try await client.mediaSegments(itemID: episode.id).allSatisfy { $0.itemID == episode.id })
        try await client.signOut()
    }

    @Test func playbackInfoAndDirectStreamURL() async throws {
        let client = try await LiveServer.signedInClient()
        guard let movie = try await firstItem(of: .movie, client: client) else { return }
        let profile = DeviceProfile(
            maxStreamingBitrate: 120_000_000,
            maxStaticBitrate: 120_000_000,
            directPlayProfiles: [
                DirectPlayProfile(
                    type: .video,
                    container: "mkv,mp4,m4v,mov,avi,ts,webm",
                    videoCodec: "h264,hevc,av1,vp9,mpeg2video,vc1",
                    audioCodec: "aac,ac3,eac3,dts,truehd,flac,mp3,opus"
                ),
            ],
            transcodingProfiles: [
                TranscodingProfile(type: .video, container: "ts", videoCodec: "h264", audioCodec: "aac", protocolName: "hls"),
            ],
            subtitleProfiles: ["subrip", "ass", "pgssub", "vtt"].map { SubtitleProfile(format: $0, method: "External") }
                + ["subrip", "ass", "pgssub"].map { SubtitleProfile(format: $0, method: "Embed") }
        )
        let info = try await client.playbackInfo(PlaybackInfoRequest(
            itemID: movie.id,
            maxStreamingBitrate: 120_000_000,
            deviceProfile: profile
        ))
        #expect(info.errorCode == nil)
        #expect(info.playSessionID != nil)
        let source = try #require(info.mediaSources.first)
        #expect(!source.streams.isEmpty)
        let url = try #require(source.directPlayURL ?? source.transcodingURL)
        #expect(url.host() == LiveServer.url?.host())

        if let directPlayURL = source.directPlayURL {
            var request = URLRequest(url: directPlayURL)
            request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
            let (_, response) = try await URLSession.shared.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 206)
        }
        try await client.signOut()
    }

    /// Reports 30 percent, because the server discards a position near either end of an item.
    @Test func playbackReportsMoveResumePosition() async throws {
        let client = try await LiveServer.signedInClient()
        let candidates = try await client.items(ItemQuery(kinds: [.episode], limit: 50)).items
        guard let episode = candidates.first(where: {
            !$0.userState.isPlayed && $0.userState.playbackPosition == .zero && ($0.runTime?.rawValue ?? 0) > 0
        }), let runTime = episode.runTime else { return }

        let position = Ticks(rawValue: runTime.rawValue * 3 / 10)
        let report = PlaybackReport(itemID: episode.id, position: position, playMethod: .directPlay)
        do {
            try await client.reportPlaybackStart(report)
            try await client.reportPlaybackProgress(report)
            try await client.reportPlaybackStopped(report)
            let after = try await client.item(id: episode.id)
            #expect(after.userState.playbackPosition == position)
            #expect(try await client.resumeItems(limit: 50).contains { $0.id == episode.id })
        } catch {
            _ = try? await client.setPlayed(false, itemID: episode.id)
            throw error
        }

        let restored = try await client.setPlayed(false, itemID: episode.id)
        #expect(restored.playbackPosition == .zero)
        #expect(!restored.isPlayed)
        try await client.signOut()
    }

    @Test func favoriteRoundTrip() async throws {
        let client = try await LiveServer.signedInClient()
        guard let movie = try await firstItem(of: .movie, client: client) else { return }
        let original = movie.userState.isFavorite
        #expect(try await client.setFavorite(!original, itemID: movie.id).isFavorite == !original)
        #expect(try await client.setFavorite(original, itemID: movie.id).isFavorite == original)
        try await client.signOut()
    }

    /// Pins the ATS configuration: plain HTTP to a public hostname is refused before it connects.
    @Test func plainHTTPToAHostnameIsBlocked() async throws {
        let client = LiveJellyfinClient(
            serverURL: URL(string: "http://example.com")!,
            device: DeviceIdentity(clientName: "Test", clientVersion: "1", deviceName: "Test", deviceID: "ats-check")
        )
        await #expect(throws: JellyfinError.insecureConnectionBlocked) {
            _ = try await client.serverInfo()
        }
    }
}
