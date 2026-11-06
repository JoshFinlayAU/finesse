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
    /// A missing capability fails the test rather than passing without checking anything.
    private func firstItem(of kind: ItemKind, client: LiveJellyfinClient) async throws -> MediaItem {
        try #require(
            try await client.items(ItemQuery(kinds: [kind], limit: 1)).items.first,
            "The test server should have at least one of \(kind)"
        )
    }

    /// Some series have no episodes on disk, so look for one that can exercise the whole hierarchy.
    private func seriesWithEpisodes(client: LiveJellyfinClient) async throws -> (show: MediaItem, season: MediaItem, episode: MediaItem) {
        let shows = try await client.items(ItemQuery(kinds: [.series], limit: 100)).items
        for show in shows {
            for season in try await client.seasons(seriesID: show.id) {
                if let episode = try await client.episodes(seriesID: show.id, seasonID: season.id).first {
                    return (show, season, episode)
                }
            }
        }
        Issue.record("None of the first \(shows.count) series has an episode")
        throw JellyfinError.notFound
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
        #expect(try await client.isQuickConnectEnabled(), "The test server should have Quick Connect on")
        let request = try await client.startQuickConnect()
        #expect(!request.code.isEmpty)
        let status = try await client.quickConnectStatus(request)
        #expect(!status.isAuthenticated)
    }

    @Test func anExpiredQuickConnectSecretIsReportedAsExpired() async throws {
        let client = try LiveServer.makeClient()
        let gone = QuickConnectRequest(code: "000000", secret: "not-a-real-secret", isAuthenticated: false)
        await #expect(throws: JellyfinError.quickConnectExpired) {
            _ = try await client.quickConnectStatus(gone)
        }
    }

    @Test func homeHubsDecode() async throws {
        let client = try await LiveServer.signedInClient()
        let resume = try await client.resumeItems(limit: 10)
        #expect(resume.allSatisfy { $0.resumePosition != nil })
        let nextUp = try await client.nextUp(limit: 10)
        #expect(nextUp.allSatisfy { $0.kind == .episode && !$0.id.isEmpty })
        let latest = try await client.latestItems(libraryID: nil, limit: 10)
        #expect(!latest.isEmpty, "A library with media should have recently added items")
        #expect(latest.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
        try await client.signOut()
    }

    @Test func libraryPagesDoNotOverlap() async throws {
        let client = try await LiveServer.signedInClient()
        let libraries = try await client.libraries()
        #expect(!libraries.isEmpty)
        var checkedAPage = false
        for library in libraries where library.kind == .movies || library.kind == .shows {
            let kind: ItemKind = library.kind == .movies ? .movie : .series
            let first = try await client.items(ItemQuery(libraryID: library.id, kinds: [kind], limit: 5))
            #expect(first.items.allSatisfy { $0.kind == kind })
            guard first.hasMore else { continue }
            checkedAPage = true
            let second = try await client.items(ItemQuery(libraryID: library.id, kinds: [kind], startIndex: 5, limit: 5))
            #expect(second.startIndex == 5)
            #expect(Set(first.items.map(\.id)).isDisjoint(with: second.items.map(\.id)))
        }
        #expect(checkedAPage, "No library had a second page, so nothing was compared")
        try await client.signOut()
    }

    @Test func everySortIsAccepted() async throws {
        let client = try await LiveServer.signedInClient()
        for sort in ItemSort.allCases {
            let page = try await client.items(ItemQuery(kinds: [.movie], sort: sort, direction: .descending, limit: 2))
            #expect(!page.items.isEmpty, "\(sort) returned nothing")
        }
        try await client.signOut()
    }

    /// Being accepted doesn't show a sort does anything, so check the order that comes back.
    @Test func sortsReallyOrderTheResults() async throws {
        let client = try await LiveServer.signedInClient()
        func movies(_ sort: ItemSort, _ direction: SortDirection) async throws -> [MediaItem] {
            try await client.items(ItemQuery(kinds: [.movie], sort: sort, direction: direction, limit: 30)).items
        }

        let ascending = try await movies(.name, .ascending)
        let descending = try await movies(.name, .descending)
        #expect(ascending.first?.id != descending.first?.id)

        let ratings = try await movies(.communityRating, .descending).compactMap(\.communityRating)
        #expect(ratings.count >= 2)
        #expect(ratings == ratings.sorted(by: >))

        let lengths = try await movies(.runTime, .descending).compactMap(\.runTime)
        #expect(lengths.count >= 2)
        #expect(lengths == lengths.sorted(by: >))

        let years = try await movies(.releaseDate, .ascending).compactMap(\.productionYear)
        #expect(years.count >= 2)
        #expect(years == years.sorted())
        try await client.signOut()
    }

    @Test func filtersNarrowTheResults() async throws {
        let client = try await LiveServer.signedInClient()
        let options = try await client.filterOptions(libraryID: nil, kinds: [.movie])
        try #require(options.genres.count >= 2, "The test server should offer at least two genres")
        let all = try await client.items(ItemQuery(kinds: [.movie], limit: 1)).totalCount

        var one = ItemQuery(kinds: [.movie], limit: 1)
        one.filter.genres = [options.genres[0]]
        let onePage = try await client.items(one)
        #expect(onePage.totalCount < all, "Filtering by genre should narrow the results")
        let match = try #require(onePage.items.first)
        #expect(try await client.item(id: match.id).genres.contains(options.genres[0]))

        // Several genres widen the result, because the server treats them as any-of.
        var other = one
        other.filter.genres = [options.genres[1]]
        var both = one
        both.filter.genres = Array(options.genres.prefix(2))
        let oneCount = onePage.totalCount
        let otherCount = try await client.items(other).totalCount
        let bothCount = try await client.items(both).totalCount
        #expect(bothCount >= max(oneCount, otherCount))
        #expect(bothCount <= oneCount + otherCount)

        var unplayed = ItemQuery(kinds: [.movie], limit: 5)
        unplayed.filter.isPlayed = false
        let unplayedPage = try await client.items(unplayed)
        #expect(!unplayedPage.items.isEmpty)
        #expect(unplayedPage.items.allSatisfy { !$0.userState.isPlayed })
        try await client.signOut()
    }

    @Test func searchFindsAKnownTitle() async throws {
        let client = try await LiveServer.signedInClient()
        let movie = try await firstItem(of: .movie, client: client)
        let word = try #require(movie.name.split(separator: " ").map(String.init).max(by: { $0.count < $1.count }))
        let results = try await client.search(term: word, kinds: [.movie], limit: 100)
        #expect(results.contains { $0.id == movie.id })
        try await client.signOut()
    }

    @Test func movieDetailAndImage() async throws {
        let client = try await LiveServer.signedInClient()
        let listed = try await client.items(ItemQuery(kinds: [.movie], limit: 50)).items
        let withArt = try #require(listed.first { $0.images.primaryTag != nil }, "No movie in the first 50 has artwork")
        let movie = try await client.item(id: withArt.id)
        #expect(movie.kind == .movie)
        _ = try await client.similarItems(id: movie.id, limit: 3)
        let url = try #require(client.imageURL(
            itemID: movie.id,
            kind: .primary,
            tag: movie.images.primaryTag,
            index: nil,
            maxWidth: 100
        ))
        let (image, response) = try await URLSession.shared.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(!image.isEmpty)
        try await client.signOut()
    }

    @Test func showHierarchy() async throws {
        let client = try await LiveServer.signedInClient()
        let (show, season, episode) = try await seriesWithEpisodes(client: client)
        #expect(try await client.item(id: show.id).kind == .series)
        #expect(season.kind == .season)
        let detail = try await client.item(id: episode.id)
        #expect(detail.kind == .episode)
        #expect(detail.seriesID == show.id)
        #expect(detail.seasonID == season.id)
        _ = try await client.nextUp(seriesID: show.id)
        #expect(try await client.mediaSegments(itemID: episode.id).allSatisfy { $0.itemID == episode.id })
        try await client.signOut()
    }

    @Test func playbackInfoAndDirectStreamURL() async throws {
        let client = try await LiveServer.signedInClient()
        let movie = try await firstItem(of: .movie, client: client)
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
        } else {
            #expect(source.supportsTranscoding, "With no direct play URL, the only way left is a transcode")
        }
        try await client.signOut()
    }

    /// Reports 30 percent, because the server discards a position near either end of an item.
    @Test func playbackReportsMoveResumePosition() async throws {
        let client = try await LiveServer.signedInClient()
        let candidates = try await client.items(ItemQuery(kinds: [.episode], limit: 200)).items
        let episode = try #require(candidates.first {
            !$0.userState.isPlayed && $0.userState.playbackPosition == .zero && ($0.runTime?.rawValue ?? 0) > 0
        }, "None of the first 200 episodes is untouched")
        let runTime = try #require(episode.runTime)

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
        let movie = try await firstItem(of: .movie, client: client)
        let original = movie.userState.isFavorite
        #expect(try await client.setFavorite(!original, itemID: movie.id).isFavorite == !original)
        #expect(try await client.setFavorite(original, itemID: movie.id).isFavorite == original)
        try await client.signOut()
    }
}
