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
                deviceID: "finesse-playback-tracks-tests"
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
        engines: [EngineCapabilities] = EngineCapabilities.routingOrder,
        _ body: (PlaybackSession, LiveJellyfinClient) async throws -> Void
    ) async throws {
        let client = try await LiveServer.signedInClient()
        guard (try? await client.item(id: itemID)) != nil else {
            Issue.record("Item \(itemID) is no longer in the library, so this test played nothing")
            return
        }
        let session = PlaybackSession(client: client, itemID: itemID, startPosition: Ticks(seconds: start), engines: engines)
        try await session.start()
        let engine = try #require(session.engine)
        #expect(engine.kind == kind)
        let view = show(engine)
        defer { view?.removeFromSuperview() }
        #expect(try await waitUntil { engine.state == .playing && engine.position.seconds > start + 1 })

        // Cleans up even when the test fails, so a failure can't leave a resume position behind.
        var failure: (any Error)?
        do {
            try await body(session, client)
        } catch {
            failure = error
        }
        await session.stop()
        try await client.reportPlaybackStopped(PlaybackReport(itemID: itemID, position: .zero, playMethod: .directPlay))
        if let failure {
            throw failure
        }
    }

    /// The server remembers each user's last audio choice per item from progress reports,
    /// which sets the default next time.
    private func remember(audio: Int, on itemID: String) async throws -> Int? {
        let client = try await LiveServer.signedInClient()
        let report = PlaybackReport(itemID: itemID, position: .zero, playMethod: .directPlay, audioStreamIndex: audio)
        try await client.reportPlaybackStart(report)
        try await client.reportPlaybackProgress(report)
        try await client.reportPlaybackStopped(report)
        let info = try await client.playbackInfo(PlaybackInfoRequest(itemID: itemID, deviceProfile: DeviceProfileBuilder.make()))
        return info.mediaSources.first?.defaultAudioStreamIndex
    }

    /// AVPlayer only reaches this file's first audio track, so a remembered second one needs mpv.
    @Test func unreachableDefaultAudioStartsOnMpvWithThatTrack() async throws {
        guard try await remember(audio: 3, on: Item.avMultiAudio) == 3 else {
            Issue.record("The server did not remember the audio choice, so this test proves nothing")
            return
        }
        try await withPlayback(Item.avMultiAudio, start: 600, expecting: .mpv) { session, _ in
            let engine = try #require(session.engine as? MPVEngine)
            #expect(engine.selectedAudioTrackID == 3)
            #expect(try await waitUntil(timeout: .seconds(10)) { engine.activeAudioTrackID == 3 })
            mark("default audio 3 playing on mpv")
            try await Task.sleep(for: .seconds(4))

            // Nothing else needs mpv now, but AVPlayer can't reach this track, so it has to stay.
            try await session.selectSubtitleTrack(id: nil)
            let after = try #require(session.engine as? MPVEngine)
            let view = show(after)
            defer { view?.removeFromSuperview() }
            #expect(try await waitUntil { after.state == .playing })
            #expect(try await waitUntil(timeout: .seconds(10)) { after.activeAudioTrackID == 3 })
            mark("subtitles off, still on mpv with audio 3")
        }
        #expect(try await remember(audio: 2, on: Item.avMultiAudio) == 2)
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
        #expect(try await remember(audio: 1, on: Item.mpvMultiAudio) == 1)
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
        #expect(try await remember(audio: 2, on: Item.avMultiAudio) == 2)
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
            #expect(await first.activeTrackID(.audible) == 2)
            try await Task.sleep(for: .seconds(4))

            // AVPlayer only exposes one of this file's two audio tracks, so this has to move.
            #expect(await first.selectableTrackCount(.audible) < first.audioTracks.count)
            let before = first.position
            try await session.selectAudioTrack(id: 3)
            let mpv = try #require(session.engine as? MPVEngine)
            let view = show(mpv)
            defer { view?.removeFromSuperview() }
            #expect(try await waitUntil { mpv.state == .playing })
            #expect(abs(mpv.position.seconds - before.seconds) < 15)
            #expect(try await waitUntil(timeout: .seconds(10)) { mpv.activeAudioTrackID == 3 })
            mark("moved to mpv for audio track 3")
            try await Task.sleep(for: .seconds(4))

            try await session.selectSubtitleTrack(id: 0)
            #expect(try await waitUntil(timeout: .seconds(10)) { mpv.activeSubtitleTrackID == 0 })
            #expect(session.engine === mpv)
            mark("external subrip on, same engine")
            try await Task.sleep(for: .seconds(15))

            try await session.selectSubtitleTrack(id: nil)
            #expect(session.engine === mpv)
            #expect(mpv.activeAudioTrackID == 3)
            mark("subtitles off, audio choice kept on mpv")
            try await Task.sleep(for: .seconds(4))
        }
        #expect(try await remember(audio: 2, on: Item.avMultiAudio) == 2)
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

    /// AVPlayer takes this title in real routing, so mpv only gets it with AVPlayer left out.
    @Test func mpvSelectsMovText() async throws {
        try await withPlayback(Item.avMovText, start: 900, expecting: .mpv, engines: [.mpv]) { session, _ in
            let engine = try #require(session.engine as? MPVEngine)
            try await session.selectSubtitleTrack(id: 2)
            #expect(try await waitUntil(timeout: .seconds(5)) { engine.activeSubtitleTrackID == 2 })
            mark("mpv mov_text on")
            try await Task.sleep(for: .seconds(35))
        }
    }

    /// Finding 8: what the user does before the engine is ready has to stick, on each engine.
    private func directPlayEngine(_ itemID: String, expecting kind: PlaybackEngineKind, start: TimeInterval) async throws -> (any PlaybackEngine, PlaybackLoadRequest) {
        let client = try await LiveServer.signedInClient()
        let info = try await client.playbackInfo(PlaybackInfoRequest(itemID: itemID, deviceProfile: DeviceProfileBuilder.make()))
        let source = try #require(info.mediaSources.first, "Item \(itemID) is no longer in the library")
        let route = try PlaybackRouter.route(sources: [source], subtitle: .off).get()
        #expect(route.engine == kind)
        let request = PlaybackLoadRequest(url: route.url, startPosition: Ticks(seconds: start), streams: source.streams, audioStreamIndex: route.audioStreamIndex)
        return (PlaybackSession.makeDefaultEngine(route.engine), request)
    }

    @Test(arguments: [(PlaybackEngineKind.avPlayer, Item.avMovText), (.mpv, Item.mpvMultiAudio)])
    func pauseStraightAfterLoadSticks(_ kind: PlaybackEngineKind, _ itemID: String) async throws {
        let (engine, request) = try await directPlayEngine(itemID, expecting: kind, start: 600)
        let view = show(engine)
        defer { view?.removeFromSuperview() }
        engine.load(request)
        engine.pause()

        #expect(try await waitUntil { engine.state == .paused }, "State \(String(describing: engine.state))")
        try await Task.sleep(for: .seconds(1))
        let held = engine.position.seconds
        try await Task.sleep(for: .seconds(4))
        #expect(engine.state == .paused)
        #expect(abs(engine.position.seconds - held) < 0.5, "Should not be moving: \(held) then \(engine.position.seconds)")

        engine.play()
        #expect(try await waitUntil { engine.state == .playing })
        engine.stop()
    }

    @Test(arguments: [(PlaybackEngineKind.avPlayer, Item.avMovText), (.mpv, Item.mpvMultiAudio)])
    func seekStraightAfterLoadSticks(_ kind: PlaybackEngineKind, _ itemID: String) async throws {
        let (engine, request) = try await directPlayEngine(itemID, expecting: kind, start: 600)
        let view = show(engine)
        defer { view?.removeFromSuperview() }
        engine.load(request)
        engine.seek(to: Ticks(seconds: 1200))

        #expect(try await waitUntil { engine.state == .playing })
        try await Task.sleep(for: .seconds(3))
        #expect(engine.position.seconds >= 1200 && engine.position.seconds < 1230, "Position \(engine.position.seconds)")
        engine.stop()
    }

    /// Paused, in both directions on real engines. This item starts on mpv for its default
    /// external subtitle, AVPlayer takes over with subtitles off, and only mpv reaches its audio 3.
    @Test func pausedStaysPausedAcrossMovesBetweenRealEngines() async throws {
        #expect(try await remember(audio: 2, on: Item.avMultiAudio) == 2)
        try await withPlayback(Item.avMultiAudio, start: 600, expecting: .mpv) { session, _ in
            await session.pause()
            let onMpv = try #require(session.engine as? MPVEngine)
            #expect(try await waitUntil { onMpv.state == .paused })
            try await Task.sleep(for: .seconds(1))
            let held = onMpv.position

            try await session.selectSubtitleTrack(id: nil)
            let onAVPlayer = try #require(session.engine as? AVPlayerEngine)
            let view = show(onAVPlayer)
            defer { view?.removeFromSuperview() }
            #expect(session.isPaused)
            #expect(try await waitUntil { onAVPlayer.state == .paused }, "State \(String(describing: onAVPlayer.state))")
            try await Task.sleep(for: .seconds(4))
            #expect(onAVPlayer.state == .paused)
            #expect(abs(onAVPlayer.position.seconds - held.seconds) < 2, "\(held.seconds) then \(onAVPlayer.position.seconds)")
            mark("moved to avplayer, still paused at \(onAVPlayer.position.seconds)")

            try await session.selectAudioTrack(id: 3)
            let backOnMpv = try #require(session.engine as? MPVEngine)
            let mpvView = show(backOnMpv)
            defer { mpvView?.removeFromSuperview() }
            #expect(session.isPaused)
            #expect(try await waitUntil { backOnMpv.state == .paused }, "State \(String(describing: backOnMpv.state))")
            try await Task.sleep(for: .seconds(4))
            #expect(backOnMpv.state == .paused)
            #expect(abs(backOnMpv.position.seconds - held.seconds) < 2, "\(held.seconds) then \(backOnMpv.position.seconds)")
            mark("moved to mpv, still paused at \(backOnMpv.position.seconds)")

            await session.play()
            #expect(try await waitUntil { backOnMpv.state == .playing })
            #expect(!session.isPaused)
            let resumed = backOnMpv.position
            try await Task.sleep(for: .seconds(3))
            #expect(backOnMpv.position > resumed, "Should be moving again")
        }
        #expect(try await remember(audio: 2, on: Item.avMultiAudio) == 2)
    }

    /// Real transcodes on a server that only does them in software, so this runs only when asked,
    /// while a script reads the host's process list. Set FINESSE_TRANSCODE_PROBE to run it.
    @Test(.enabled(if: LiveServer.environment["FINESSE_TRANSCODE_PROBE"] != nil))
    func aTranscodeTrackChangeEndsTheOldJob() async throws {
        let client = try await LiveServer.signedInClient()
        var profile = DeviceProfileBuilder.make()
        profile.directPlayProfiles = []
        profile.maxStreamingBitrate = 1_500_000
        let session = PlaybackSession(
            client: client,
            itemID: Item.mpvMultiAudio,
            startPosition: Ticks(seconds: 300),
            deviceProfile: profile
        )
        try await session.start()
        #expect(session.route?.method == .transcode)
        let engine = try #require(session.engine)
        let view = show(engine)
        defer { view?.removeFromSuperview() }
        #expect(try await waitUntil { engine.state == .playing })
        print("PROBE \(Date.now.timeIntervalSince1970) playing first transcode")
        try await Task.sleep(for: .seconds(8))

        try await session.selectAudioTrack(id: 2)
        print("PROBE \(Date.now.timeIntervalSince1970) track changed")
        #expect(session.route?.method == .transcode)
        let second = try #require(session.engine)
        let secondView = show(second)
        defer { secondView?.removeFromSuperview() }
        #expect(try await waitUntil { second.state == .playing })
        try await Task.sleep(for: .seconds(10))

        // The server has to have honoured it, which shows in the URL it built.
        let audioURL = try #require(session.route?.url.absoluteString)
        #expect(audioURL.contains("AudioStreamIndex=2"), "Should stream the audio asked for")

        print("PROBE \(Date.now.timeIntervalSince1970) stopping")
        await session.stop()
        print("PROBE \(Date.now.timeIntervalSince1970) stopped")
        try await Task.sleep(for: .seconds(15))
        try await client.reportPlaybackStopped(PlaybackReport(itemID: Item.mpvMultiAudio, position: .zero, playMethod: .directPlay))
        #expect(try await remember(audio: 1, on: Item.mpvMultiAudio) == 1)
    }

    /// A PGS subtitle has to be burned in, so the server's URL shows whether it listened.
    @Test(.enabled(if: LiveServer.environment["FINESSE_TRANSCODE_PROBE"] != nil))
    func aTranscodeBurnsInTheSubtitleChosenAndOffRemovesIt() async throws {
        let client = try await LiveServer.signedInClient()
        var profile = DeviceProfileBuilder.make()
        profile.directPlayProfiles = []
        profile.maxStreamingBitrate = 1_500_000
        let session = PlaybackSession(client: client, itemID: Item.pgs, startPosition: Ticks(seconds: 900), deviceProfile: profile)
        try await session.start()
        #expect(session.route?.method == .transcode)

        try await session.selectSubtitleTrack(id: 2)
        #expect(session.route?.subtitleStreamIndex == 2)
        let chosen = try #require(session.route?.url.absoluteString)
        #expect(chosen.contains("SubtitleStreamIndex=2"), "Should burn in the subtitle asked for")
        let engine = try #require(session.engine)
        let view = show(engine)
        defer { view?.removeFromSuperview() }
        #expect(try await waitUntil { engine.state == .playing })

        try await session.selectSubtitleTrack(id: nil)
        #expect(session.route?.subtitleStreamIndex == nil)
        let off = try #require(session.route?.url.absoluteString)
        #expect(!off.contains("SubtitleStreamIndex=2"), "Off should stop burning it in")
        let second = try #require(session.engine)
        let secondView = show(second)
        defer { secondView?.removeFromSuperview() }
        #expect(try await waitUntil { second.state == .playing })

        await session.stop()
        try await client.reportPlaybackStopped(PlaybackReport(itemID: Item.pgs, position: .zero, playMethod: .directPlay))
    }

    /// Causes a genuine AVPlayer failure by telling the router it can play an MKV, which it can't.
    /// That fails while loading rather than mid-playback, but it's the same path out of the engine.
    @Test func avPlayerFailingForRealMovesToMpvAtThePosition() async throws {
        // A remembered second audio track would send this to mpv before AVPlayer ever failed.
        #expect(try await remember(audio: 1, on: Item.mpvMultiAudio) == 1)
        let client = try await LiveServer.signedInClient()
        guard let item = try? await client.item(id: Item.mpvMultiAudio) else {
            Issue.record("Item is no longer in the library, so this test played nothing")
            return
        }
        var pretending = EngineCapabilities.avPlayer
        pretending.containers.insert("mkv")
        pretending.embeddedSubtitleCodecs.insert("subrip")
        let model = PlayerModel(
            client: client,
            request: PlaybackRequest(item: item, resumePosition: Ticks(seconds: 300)),
            engines: [pretending, .mpv]
        )
        await model.start()
        #expect(model.engine?.kind == .avPlayer)
        mark("avplayer given an mkv")

        let deadline = ContinuousClock.now + .seconds(60)
        while model.engine?.kind != .mpv || model.engine?.state != .playing, ContinuousClock.now < deadline {
            await model.tick()
            if case .failed = model.phase { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        let engine = try #require(model.engine as? MPVEngine, "Phase \(model.phase)")
        let view = show(engine)
        defer { view?.removeFromSuperview() }
        #expect(model.phase == .playing)
        #expect(engine.state == .playing)
        #expect(engine.position.seconds >= 300 && engine.position.seconds < 330)
        mark("moved to mpv at \(engine.position.seconds)")
        try await Task.sleep(for: .seconds(6))
        #expect(engine.position.seconds > 303)

        await model.exit()
        try await client.reportPlaybackStopped(PlaybackReport(itemID: item.id, position: .zero, playMethod: .directPlay))
    }

    /// Plays the last seconds of an episode on each engine and checks the server moves on.
    @Test(arguments: [PlaybackEngineKind.avPlayer, .mpv])
    func episodeEndAdvancesToNextEpisodeAndServerMarksItPlayed(_ kind: PlaybackEngineKind) async throws {
        let client = try await LiveServer.signedInClient()
        guard let (episode, next) = try await findEpisode(for: kind, client: client), let runTime = episode.runTime else {
            Issue.record("No suitable \(kind) episode, so this test played nothing")
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
