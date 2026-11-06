import AVFoundation
import Foundation
import Testing
import UIKit
@testable import FinEsse

private enum LiveServer {
    static let environment = ProcessInfo.processInfo.environment
    static let isConfigured = environment["JELLYFIN_URL"] != nil
        && environment["JELLYFIN_USERNAME"] != nil
        && environment["JELLYFIN_PASSWORD"] != nil

    static func signedInClient() async throws -> LiveJellyfinClient {
        let client = LiveJellyfinClient(
            serverURL: try #require(environment["JELLYFIN_URL"].flatMap(URL.init(string:))),
            device: DeviceIdentity(
                clientName: "Finesse Playback Tests",
                clientVersion: "1.0",
                deviceName: "Simulator",
                deviceID: "finesse-playback-tests"
            )
        )
        _ = try await client.signIn(
            username: try #require(environment["JELLYFIN_USERNAME"]),
            password: try #require(environment["JELLYFIN_PASSWORD"])
        )
        return client
    }
}

/// Switches tracks on real media and checks what each engine really selected, and prints
/// `MARK` lines so screenshots of the same moments can be reviewed. Items are chosen for their
/// streams; a test skips itself if its item has left the library. Saved positions are put back.
@MainActor
@Suite(.serialized, .enabled(if: LiveServer.isConfigured, "JELLYFIN_* variables not set"))
struct PlaybackTracksEndToEndTests {
    private enum Item {
        /// mkv, two audio languages, embedded subrip.
        static let mpvMultiAudio = "f2f752c9de4511295d96bf36941f29ee"
        /// mkv, PGS subtitles.
        static let pgs = "a5a5fe5933288e0c45392d41a148fad9"
        /// mkv, ASS with several styles and override tags, first positioned line at 5s.
        static let styledASS = "3a666bec1706e7a360e93727d4c0bccd"
        /// mp4, H.264, external subrip numbered before the file's streams, two audio tracks.
        static let avMultiAudio = "5591e677a09876112cf8ae42bf6c4e6f"
        /// mp4, three mov_text tracks.
        static let avMovText = "75c2da7ae8730a3faa40e7b6f09eefee"
    }

    private func mark(_ text: String) {
        print("MARK \(Date.now.timeIntervalSince1970) \(text)")
    }

    private func waitUntil(timeout: Duration = .seconds(45), _ condition: @MainActor () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        return condition()
    }

    private func show(_ engine: any PlaybackEngine) -> UIView? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first
        guard let window else {
            return nil
        }
        let view = engine.makeRenderView()
        view.frame = window.bounds
        window.addSubview(view)
        return view
    }

    /// Starts the item if it still exists, runs `body`, stops, and clears the saved position.
    private func withPlayback(
        _ itemID: String,
        start: TimeInterval,
        expecting kind: PlaybackEngineKind,
        _ body: (PlaybackSession, LiveJellyfinClient) async throws -> Void
    ) async throws {
        let client = try await LiveServer.signedInClient()
        guard (try? await client.item(id: itemID)) != nil else {
            print("SKIP item \(itemID) is no longer in the library")
            return
        }
        let session = PlaybackSession(client: client, itemID: itemID, startPosition: Ticks(seconds: start))
        try await session.start()
        let engine = try #require(session.engine)
        #expect(engine.kind == kind)
        let view = show(engine)
        defer { view?.removeFromSuperview() }
        #expect(try await waitUntil { engine.state == .playing && engine.position.seconds > start + 1 })

        try await body(session, client)

        await session.stop()
        try await client.reportPlaybackStopped(PlaybackReport(itemID: itemID, position: .zero, playMethod: .directPlay))
    }

    @Test func mpvSwitchesAudioAndSubtitlesOnTheSameEngine() async throws {
        try await withPlayback(Item.mpvMultiAudio, start: 600, expecting: .mpv) { session, _ in
            let engine = try #require(session.engine as? MPVEngine)
            #expect(engine.audioTracks.count == 2)
            // The server chooses the starting tracks, so switch to whichever isn't playing.
            let startingAudio = try #require(engine.selectedAudioTrackID)
            #expect(engine.activeAudioTrackID == startingAudio)
            let otherAudio = try #require(engine.audioTracks.first { $0.id != startingAudio }?.id)

            try await session.selectAudioTrack(id: otherAudio)
            #expect(try await waitUntil(timeout: .seconds(5)) { engine.activeAudioTrackID == otherAudio })
            #expect(session.engine === engine)
            mark("mpv audio track \(otherAudio) active")

            try await session.selectSubtitleTrack(id: 3)
            #expect(try await waitUntil(timeout: .seconds(5)) { engine.activeSubtitleTrackID == 3 })
            mark("mpv subrip on")
            try await Task.sleep(for: .seconds(25))

            let before = engine.position
            try await session.selectSubtitleTrack(id: nil)
            #expect(try await waitUntil(timeout: .seconds(5)) { engine.activeSubtitleTrackID == nil })
            #expect(session.engine === engine)
            #expect(engine.position >= before)
            mark("mpv subrip off")
            try await Task.sleep(for: .seconds(6))
        }
    }

    @Test func mpvSelectsPGS() async throws {
        try await withPlayback(Item.pgs, start: 900, expecting: .mpv) { session, _ in
            let engine = try #require(session.engine as? MPVEngine)
            try await session.selectSubtitleTrack(id: 2)
            #expect(try await waitUntil(timeout: .seconds(5)) { engine.activeSubtitleTrackID == 2 })
            mark("mpv pgs on")
            try await Task.sleep(for: .seconds(40))
        }
    }

    @Test func mpvSelectsStyledASS() async throws {
        try await withPlayback(Item.styledASS, start: 2, expecting: .mpv) { session, _ in
            let engine = try #require(session.engine as? MPVEngine)
            try await session.selectSubtitleTrack(id: 2)
            #expect(try await waitUntil(timeout: .seconds(5)) { engine.activeSubtitleTrackID == 2 })
            mark("mpv ass on, position \(engine.position.seconds)")
            try await Task.sleep(for: .seconds(40))
        }
    }

    @Test func avPlayerSwitchesAudioAndMovesToMpvForAnExternalSubtitleAndBack() async throws {
        // The server turns this item's external subtitle on by default, so it starts on mpv.
        try await withPlayback(Item.avMultiAudio, start: 600, expecting: .mpv) { session, _ in
            let starting = try #require(session.engine as? MPVEngine)
            #expect(try await waitUntil(timeout: .seconds(10)) { starting.activeSubtitleTrackID == 0 })
            mark("starts on mpv, external subrip on")
            try await Task.sleep(for: .seconds(20))

            let beforeOff = starting.position
            try await session.selectSubtitleTrack(id: nil)
            let first = try #require(session.engine as? AVPlayerEngine)
            let firstView = show(first)
            defer { firstView?.removeFromSuperview() }
            #expect(try await waitUntil { first.state == .playing })
            #expect(abs(first.position.seconds - beforeOff.seconds) < 15)
            mark("moved to avplayer, subtitles off")
            print("OPTIONS audible \(await first.selectableTrackCount(.audible)) legible \(await first.selectableTrackCount(.legible)) server audio \(first.audioTracks.count)")
            #expect(await first.activeTrackID(.audible) == 2)

            try await session.selectAudioTrack(id: 3)
            var active: Int?
            for _ in 0..<25 {
                active = await first.activeTrackID(.audible)
                if active == 3 { break }
                try await Task.sleep(for: .milliseconds(200))
            }
            #expect(active == 3)
            #expect(session.engine === first)
            mark("avplayer audio track 3 active")
            try await Task.sleep(for: .seconds(4))

            let before = first.position
            try await session.selectSubtitleTrack(id: 0)
            let mpv = try #require(session.engine as? MPVEngine)
            let view = show(mpv)
            defer { view?.removeFromSuperview() }
            #expect(try await waitUntil { mpv.state == .playing })
            #expect(abs(mpv.position.seconds - before.seconds) < 15)
            #expect(try await waitUntil(timeout: .seconds(10)) { mpv.activeSubtitleTrackID == 0 })
            #expect(mpv.selectedAudioTrackID == 3)
            #expect(try await waitUntil(timeout: .seconds(10)) { mpv.activeAudioTrackID == 3 })
            mark("back on mpv, external subrip on, audio choice kept")
            try await Task.sleep(for: .seconds(10))
        }
    }

    @Test func avPlayerSelectsMovText() async throws {
        try await withPlayback(Item.avMovText, start: 900, expecting: .avPlayer) { session, _ in
            let engine = try #require(session.engine as? AVPlayerEngine)
            try await session.selectSubtitleTrack(id: 2)
            var active: Int?
            for _ in 0..<25 {
                active = await engine.activeTrackID(.legible)
                if active == 2 { break }
                try await Task.sleep(for: .milliseconds(200))
            }
            #expect(active == 2)
            #expect(session.engine === engine)
            mark("avplayer mov_text on")
            try await Task.sleep(for: .seconds(35))
        }
    }

    /// Plays the last seconds of an episode on each engine and checks the server moves on.
    @Test(arguments: [PlaybackEngineKind.avPlayer, .mpv])
    func episodeEndAdvancesToNextEpisodeAndServerMarksItPlayed(_ kind: PlaybackEngineKind) async throws {
        let client = try await LiveServer.signedInClient()
        guard let (episode, next) = try await findEpisode(for: kind, client: client), let runTime = episode.runTime else {
            print("SKIP no suitable \(kind) episode")
            return
        }
        let model = PlayerModel(
            client: client,
            request: PlaybackRequest(item: episode, resumePosition: Ticks(seconds: runTime.seconds - 12))
        )
        await model.start()
        #expect(model.phase == .playing)
        #expect(model.engine?.kind == kind)
        let view = model.engine.flatMap(show)
        defer { view?.removeFromSuperview() }

        let deadline = ContinuousClock.now + .seconds(60)
        while model.phase == .playing, ContinuousClock.now < deadline {
            await model.tick()
            try await Task.sleep(for: .milliseconds(250))
        }
        guard case .upNext(let shown, _) = model.phase else {
            Issue.record("Expected up next, got \(model.phase), position \(model.displayPosition.seconds)")
            await model.exit()
            _ = try await client.setPlayed(false, itemID: episode.id)
            return
        }
        print("NEXT computed \(next), server chose \(shown.id) S\(shown.parentIndexNumber ?? -1)E\(shown.indexNumber ?? -1) after S\(episode.parentIndexNumber ?? -1)E\(episode.indexNumber ?? -1)")
        #expect(shown.seriesID == episode.seriesID)
        #expect(shown.id != episode.id)
        #expect(try await client.item(id: episode.id).userState.isPlayed)
        mark("\(kind) up next showing")

        await model.playNext()
        #expect(model.phase == .playing)
        #expect(model.item.id == shown.id)
        await model.exit()
        #expect(model.phase == .finished)

        _ = try await client.setPlayed(false, itemID: episode.id)
        try await client.reportPlaybackStopped(PlaybackReport(itemID: shown.id, position: .zero, playMethod: .directPlay))
    }

    /// An unwatched, normal-sized episode, because very small files on this server can be truncated.
    private func findEpisode(
        for kind: PlaybackEngineKind,
        client: LiveJellyfinClient
    ) async throws -> (MediaItem, next: String)? {
        let profile = DeviceProfileBuilder.make()
        for startIndex in stride(from: 0, to: 3000, by: 100) {
            let page = try await client.items(ItemQuery(kinds: [.episode], startIndex: startIndex, limit: 100))
            for episode in page.items where !episode.userState.isPlayed && episode.userState.playbackPosition == .zero {
                guard let seriesID = episode.seriesID, let runTime = episode.runTime, runTime.seconds > 300 else {
                    continue
                }
                let info = try await client.playbackInfo(PlaybackInfoRequest(itemID: episode.id, deviceProfile: profile))
                guard let source = info.mediaSources.first, (source.size ?? 0) > 100_000_000,
                      case .success(let route) = PlaybackRouter.route(sources: info.mediaSources),
                      route.engine == kind, route.method == .directPlay else {
                    continue
                }
                let episodes = try await client.episodes(seriesID: seriesID, seasonID: episode.seasonID)
                guard let index = episodes.firstIndex(where: { $0.id == episode.id }), index + 1 < episodes.count,
                      index == 0 else {
                    continue
                }
                return (episode, next: episodes[index + 1].id)
            }
        }
        return nil
    }
}
