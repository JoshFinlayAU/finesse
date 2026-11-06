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
