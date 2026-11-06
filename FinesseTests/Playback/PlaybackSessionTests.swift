import Foundation
import Observation
import Testing
import UIKit
@testable import FinEsse

@MainActor
@Observable
private final class FakeEngine: PlaybackEngine {
    let kind: PlaybackEngineKind
    var state = PlaybackState.idle
    var position = Ticks.zero
    var duration: Ticks?
    var audioTracks: [PlaybackTrack] = []
    var subtitleTracks: [PlaybackTrack] = []
    var selectedAudioTrackID: Int?
    var selectedSubtitleTrackID: Int?
    var loaded: PlaybackLoadRequest?
    var stopped = false
    var unreachableAudio: Set<Int> = []

    init(kind: PlaybackEngineKind) {
        self.kind = kind
    }

    func load(_ request: PlaybackLoadRequest) {
        loaded = request
        position = request.startPosition
        selectedAudioTrackID = request.audioStreamIndex
        selectedSubtitleTrackID = request.subtitleStreamIndex
        state = .playing
    }

    func play() { state = .playing }
    func pause() { state = .paused }
    func seek(to position: Ticks) { self.position = position }
    func canSelectAudioTrack(id: Int) async -> Bool { !unreachableAudio.contains(id) }
    func selectAudioTrack(id: Int) { selectedAudioTrackID = id }
    func selectSubtitleTrack(id: Int?) { selectedSubtitleTrackID = id }
    func stop() { stopped = true }
    func makeRenderView() -> UIView { UIView() }
}

@MainActor
@Suite struct PlaybackSessionTests {
    private func stream(_ index: Int, _ kind: MediaStreamKind, _ codec: String) -> MediaStreamInfo {
        var info = MediaStreamInfo(index: index, kind: kind)
        info.codec = codec
        return info
    }

    private func makeInfo() -> PlaybackInfo {
        var source = PlaybackMediaSource(id: "source")
        source.container = "mp4"
        source.supportsDirectPlay = true
        source.directPlayURL = URL(string: "http://server.invalid/direct")
        source.streams = [
            stream(0, .video, "h264"),
            stream(1, .audio, "aac"),
            stream(2, .audio, "dts"),
            stream(3, .subtitle, "pgssub"),
        ]
        return PlaybackInfo(playSessionID: "session", mediaSources: [source])
    }

    private func makeClient(_ info: PlaybackInfo) async throws -> InMemoryJellyfinClient {
        let client = InMemoryJellyfinClient()
        _ = try await client.signIn(username: "Test User", password: "password")
        await client.configure { $0.playbackInfoValue = info }
        return client
    }

    private func makeSession(_ client: InMemoryJellyfinClient, start: Ticks = .zero) -> (PlaybackSession, () -> [FakeEngine]) {
        var engines: [FakeEngine] = []
        let session = PlaybackSession(client: client, itemID: "item", startPosition: start) { kind in
            let engine = FakeEngine(kind: kind)
            engines.append(engine)
            return engine
        }
        return (session, { engines })
    }

    @Test func startSendsProfileRoutesLoadsAndReports() async throws {
        let client = try await makeClient(makeInfo())
        let (session, engines) = makeSession(client, start: Ticks(seconds: 30))

        try await session.start()

        let request = await client.playbackInfoRequests.first
        #expect(request?.deviceProfile == DeviceProfileBuilder.make())
        #expect(engines().map(\.kind) == [.avPlayer])
        #expect(engines().first?.loaded?.startPosition == Ticks(seconds: 30))
        #expect(await client.startReports.first?.position == Ticks(seconds: 30))
        #expect(await client.startReports.first?.playSessionID == "session")
        await session.stop()
    }

    @Test func serverRefusalThrowsWithoutStartingAnEngine() async throws {
        var info = makeInfo()
        info.errorCode = "NotAllowed"
        let client = try await makeClient(info)
        let (session, engines) = makeSession(client)

        await #expect(throws: PlaybackSessionError.refusedByServer("NotAllowed")) {
            try await session.start()
        }
        #expect(engines().isEmpty)
    }

    @Test func noPlayableSourceThrows() async throws {
        let client = try await makeClient(PlaybackInfo())
        let (session, _) = makeSession(client)
        await #expect(throws: PlaybackSessionError.noPlayableSource) {
            try await session.start()
        }
    }

    @Test func choosingTrackTheEngineCannotPlaySwitchesAtTheCurrentPosition() async throws {
        let client = try await makeClient(makeInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].position = Ticks(seconds: 100)

        try await session.selectSubtitleTrack(id: 3)

        #expect(engines().map(\.kind) == [.avPlayer, .mpv])
        #expect(engines()[0].stopped)
        #expect(engines()[1].loaded?.startPosition == Ticks(seconds: 100))
        #expect(engines()[1].loaded?.subtitleStreamIndex == 3)
        #expect(session.engine?.kind == .mpv)
        await session.stop()
    }

    @Test func choosingTrackTheEngineCanPlayStaysOnIt() async throws {
        let client = try await makeClient(makeInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        try await session.selectAudioTrack(id: 1)
        #expect(engines().count == 1)
        #expect(engines()[0].selectedAudioTrackID == 1)
        await session.stop()
    }

    /// An MP4 whose audio tracks AVPlayer can't switch between, as seen on the test server.
    private func makeUngroupedAudioInfo() -> PlaybackInfo {
        var info = makeInfo()
        info.mediaSources[0].streams[2] = stream(2, .audio, "ac3")
        return info
    }

    @Test func audioTheEngineCannotReachMovesToTheOtherEngineAndStaysThere() async throws {
        let client = try await makeClient(makeUngroupedAudioInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].unreachableAudio = [2]
        engines()[0].position = Ticks(seconds: 100)

        try await session.selectAudioTrack(id: 2)

        #expect(engines().map(\.kind) == [.avPlayer, .mpv])
        #expect(engines()[0].stopped)
        #expect(engines()[1].loaded?.startPosition == Ticks(seconds: 100))
        #expect(engines()[1].loaded?.audioStreamIndex == 2)

        // Nothing here needs mpv by itself, but going back would lose the audio choice.
        try await session.selectSubtitleTrack(id: nil)
        #expect(engines().count == 2)
        #expect(session.engine?.kind == .mpv)
        await session.stop()
    }

    @Test func unreachableDefaultAudioStartsOnTheOtherEngineAndReportsOnce() async throws {
        var info = makeUngroupedAudioInfo()
        info.mediaSources[0].defaultAudioStreamIndex = 2
        let client = try await makeClient(info)
        var engines: [FakeEngine] = []
        let session = PlaybackSession(client: client, itemID: "item", startPosition: Ticks(seconds: 30)) { kind in
            let engine = FakeEngine(kind: kind)
            engine.unreachableAudio = kind == .avPlayer ? [2] : []
            engines.append(engine)
            return engine
        }

        try await session.start()

        #expect(engines.map(\.kind) == [.avPlayer, .mpv])
        #expect(engines[0].stopped)
        #expect(session.engine?.kind == .mpv)
        #expect(engines[1].loaded?.audioStreamIndex == 2)
        #expect(engines[1].loaded?.startPosition == Ticks(seconds: 30))
        #expect(session.route?.engine == .mpv)
        #expect(await client.startReports.count == 1)
        #expect(await client.startReports.first?.audioStreamIndex == 2)
        await session.stop()
    }

    @Test func aMoveBackToAnEngineThatCannotReachTheAudioGoesElsewhere() async throws {
        // Starts on mpv only because of the default subtitle, with audio AVPlayer can't reach.
        var info = makeUngroupedAudioInfo()
        info.mediaSources[0].defaultAudioStreamIndex = 2
        info.mediaSources[0].defaultSubtitleStreamIndex = 3
        let client = try await makeClient(info)
        var engines: [FakeEngine] = []
        let session = PlaybackSession(client: client, itemID: "item") { kind in
            let engine = FakeEngine(kind: kind)
            engine.unreachableAudio = kind == .avPlayer ? [2] : []
            engines.append(engine)
            return engine
        }
        try await session.start()
        #expect(session.engine?.kind == .mpv)
        engines[0].position = Ticks(seconds: 50)

        try await session.selectSubtitleTrack(id: nil)

        #expect(engines.map(\.kind) == [.mpv, .avPlayer, .mpv])
        #expect(session.engine?.kind == .mpv)
        #expect(engines[2].loaded?.audioStreamIndex == 2)
        #expect(engines[2].loaded?.startPosition == Ticks(seconds: 50))
        #expect(session.route?.engine == .mpv)
        await session.stop()
    }

    @Test func reachableDefaultAudioStaysOnAVPlayer() async throws {
        var info = makeUngroupedAudioInfo()
        info.mediaSources[0].defaultAudioStreamIndex = 1
        let client = try await makeClient(info)
        let (session, engines) = makeSession(client)
        try await session.start()
        #expect(engines().map(\.kind) == [.avPlayer])
        await session.stop()
    }

    @Test func aTranscodeIsNeverMovedForItsAudio() async throws {
        var info = makeUngroupedAudioInfo()
        info.mediaSources[0].supportsDirectPlay = false
        info.mediaSources[0].supportsTranscoding = true
        info.mediaSources[0].transcodingURL = URL(string: "http://server.invalid/master.m3u8")
        info.mediaSources[0].defaultAudioStreamIndex = 2
        let client = try await makeClient(info)
        var engines: [FakeEngine] = []
        let session = PlaybackSession(client: client, itemID: "item") { kind in
            let engine = FakeEngine(kind: kind)
            engine.unreachableAudio = [2]
            engines.append(engine)
            return engine
        }
        try await session.start()
        #expect(engines.map(\.kind) == [.avPlayer])
        #expect(session.route?.method == .transcode)
        await session.stop()
    }

    @Test func audioTheEngineCanReachStaysOnIt() async throws {
        let client = try await makeClient(makeUngroupedAudioInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        try await session.selectAudioTrack(id: 2)
        #expect(engines().map(\.kind) == [.avPlayer])
        #expect(engines()[0].selectedAudioTrackID == 2)
        await session.stop()
    }

    @Test func aFailedEngineMovesToTheOtherAtTheSamePositionKeepingTracks() async throws {
        let client = try await makeClient(makeUngroupedAudioInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        try await session.selectAudioTrack(id: 2)
        engines()[0].position = Ticks(seconds: 200)
        engines()[0].state = .failed("broken")

        #expect(await session.recoverFromEngineFailure())

        #expect(engines().map(\.kind) == [.avPlayer, .mpv])
        #expect(engines()[0].stopped)
        #expect(engines()[1].loaded?.startPosition == Ticks(seconds: 200))
        #expect(engines()[1].loaded?.audioStreamIndex == 2)
        #expect(session.route?.engine == .mpv)
        #expect(await client.startReports.count == 1)
        #expect(await client.stopReports.isEmpty)
        #expect(await client.progressReports.last?.position == Ticks(seconds: 200))
        await session.stop()
    }

    @Test func aFailedEngineIsNeverTriedAgainSoThereIsNoLoop() async throws {
        let client = try await makeClient(makeUngroupedAudioInfo())
        let (session, engines) = makeSession(client)
        try await session.start()

        #expect(await session.recoverFromEngineFailure())
        #expect(!(await session.recoverFromEngineFailure()))
        #expect(!(await session.recoverFromEngineFailure()))
        #expect(engines().map(\.kind) == [.avPlayer, .mpv])

        // Nor does a later track change route back to the engine that failed.
        try await session.selectSubtitleTrack(id: nil)
        #expect(engines().count == 2)
        await session.stop()
    }

    @Test func noOtherEngineToMoveToIsAFailure() async throws {
        let client = try await makeClient(makeInfo())
        let session = PlaybackSession(client: client, itemID: "item", engines: [.avPlayer]) { FakeEngine(kind: $0) }
        try await session.start()
        #expect(!(await session.recoverFromEngineFailure()))
        await session.stop()
    }

    @Test func aFormatTheOtherEngineCannotPlayIsAFailure() async throws {
        var mpvCannot = EngineCapabilities.mpv
        mpvCannot.videoCodecs = ["vp9"]
        let client = try await makeClient(makeInfo())
        let session = PlaybackSession(client: client, itemID: "item", engines: [.avPlayer, mpvCannot]) { FakeEngine(kind: $0) }
        try await session.start()
        #expect(session.engine?.kind == .avPlayer)
        #expect(!(await session.recoverFromEngineFailure()))
        await session.stop()
    }

    @Test func stopReportsPositionBeforeStoppingEngine() async throws {
        let client = try await makeClient(makeInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].position = Ticks(seconds: 77)

        await session.stop()

        #expect(await client.stopReports.first?.position == Ticks(seconds: 77))
        #expect(engines()[0].stopped)
        #expect(session.engine == nil)
    }

    @Test func pauseIsReportedStraightAway() async throws {
        let client = try await makeClient(makeInfo())
        let (session, _) = makeSession(client)
        try await session.start()
        await session.pause()
        #expect(await client.progressReports.last?.isPaused == true)
        await session.stop()
    }
}

@Suite struct PlaybackLoadRequestTests {
    private func stream(_ index: Int, _ kind: MediaStreamKind, external: Bool = false) -> MediaStreamInfo {
        var info = MediaStreamInfo(index: index, kind: kind)
        info.isExternal = external
        return info
    }

    private func request(_ streams: [MediaStreamInfo]) -> PlaybackLoadRequest {
        PlaybackLoadRequest(url: URL(string: "http://server.invalid/direct")!, startPosition: .zero, streams: streams)
    }

    @Test func withoutExternalSubtitlesTheIndexesMatchTheFile() {
        let request = request([stream(0, .video), stream(1, .audio), stream(2, .subtitle)])
        #expect(request.fileStreamIndex(ofStream: 1) == 1)
        #expect(request.fileStreamIndex(ofStream: 2) == 2)
    }

    /// As the server returned it: external subtitle 0, video 1, audio 2 and 3.
    @Test func anExternalSubtitleNumberedFirstShiftsTheFileStreams() {
        let request = request([stream(0, .subtitle, external: true), stream(1, .video), stream(2, .audio), stream(3, .audio)])
        #expect(request.fileStreamIndex(ofStream: 0) == nil)
        #expect(request.fileStreamIndex(ofStream: 1) == 0)
        #expect(request.fileStreamIndex(ofStream: 2) == 1)
        #expect(request.fileStreamIndex(ofStream: 3) == 2)
    }

    @Test func anExternalSubtitleNumberedLastShiftsNothing() {
        let request = request([stream(0, .video), stream(1, .audio), stream(2, .subtitle, external: true)])
        #expect(request.fileStreamIndex(ofStream: 1) == 1)
        #expect(request.fileStreamIndex(ofStream: 2) == nil)
    }

    @Test func anUnknownStreamHasNoFileIndex() {
        #expect(request([stream(0, .video)]).fileStreamIndex(ofStream: 9) == nil)
    }
}
