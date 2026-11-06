import Foundation
import Testing
@testable import FinEsse

@MainActor
private final class OptionsHarness {
    let client = InMemoryJellyfinClient()
    var engines: [FakePlaybackEngine] = []
    var engine: FakePlaybackEngine { engines[engines.count - 1] }

    static func source(id: String = "source", container: String = "mp4", bitRate: Int? = 5_000_000) -> PlaybackMediaSource {
        var source = PlaybackMediaSource(id: id)
        source.container = container
        source.bitRate = bitRate
        source.supportsDirectPlay = true
        source.supportsTranscoding = true
        source.directPlayURL = URL(string: "http://server.invalid/\(id)")
        source.transcodingURL = URL(string: "http://server.invalid/\(id).m3u8")
        var video = MediaStreamInfo(index: 0, kind: .video)
        video.codec = "h264"
        var audio = MediaStreamInfo(index: 1, kind: .audio)
        audio.codec = "aac"
        source.streams = [video, audio]
        return source
    }

    func session(
        sources: [PlaybackMediaSource] = [source()],
        options: PlaybackOptions = PlaybackOptions(),
        maxBitrate: Int? = nil,
        captions: SystemCaptionStyle = SystemCaptionStyle()
    ) async throws -> PlaybackSession {
        _ = try await client.signIn(username: "Test User", password: "password")
        await client.configure { $0.playbackInfoValue = PlaybackInfo(playSessionID: "session", mediaSources: sources) }
        let session = PlaybackSession(
            client: client,
            itemID: "item",
            options: options,
            maxBitrate: maxBitrate,
            captionStyle: captions,
            makeEngine: { [unowned self] kind in
                let engine = FakePlaybackEngine(kind: kind)
                engines.append(engine)
                return engine
            }
        )
        try await session.start()
        return session
    }
}

@MainActor
@Suite struct PlaybackOptionsTests {
    @Test(arguments: [PlaybackOption.rate, .pictureMode, .subtitleStyle])
    func bothEnginesDo(option: PlaybackOption) {
        #expect(option.isSupported(by: .avPlayer))
        #expect(option.isSupported(by: .mpv))
    }

    @Test(arguments: [PlaybackOption.subtitleDelay, .audioDelay])
    func onlyMpvDoes(option: PlaybackOption) {
        #expect(!option.isSupported(by: .avPlayer))
        #expect(option.isSupported(by: .mpv))
    }

    @Test func optionsReachTheEngineAtStart() async throws {
        let harness = OptionsHarness()
        var options = PlaybackOptions()
        options.rate = 1.5
        options.pictureMode = .fill
        options.subtitleScale = 1.2
        _ = try await harness.session(options: options)
        #expect(harness.engine.applied.last == options)
    }

    @Test func aSharedOptionStaysOnTheSameEngine() async throws {
        let harness = OptionsHarness()
        let session = try await harness.session()
        #expect(harness.engine.kind == .avPlayer)
        #expect(session.availability(of: .rate) == .available)

        var options = session.options
        options.rate = 2
        try await session.setOptions(options)

        #expect(harness.engines.count == 1)
        #expect(harness.engine.applied.last?.rate == 2)
    }

    @Test(arguments: [true, false])
    func aTimingOptionMovesToMpvAtTheSamePositionAndKeepsIt(audio: Bool) async throws {
        let harness = OptionsHarness()
        let session = try await harness.session()
        harness.engine.position = Ticks(seconds: 300)
        let option: PlaybackOption = audio ? .audioDelay : .subtitleDelay
        #expect(session.availability(of: option) == .movesEngine)

        var options = session.options
        if audio { options.audioDelay = 0.5 } else { options.subtitleDelay = 0.5 }
        try await session.setOptions(options)

        #expect(harness.engines.count == 2)
        #expect(harness.engines[0].stopped)
        #expect(harness.engine.kind == .mpv)
        #expect(harness.engine.loaded?.startPosition == Ticks(seconds: 300))
        #expect(harness.engine.applied.last == options)
        #expect(session.availability(of: option) == .available)
    }

    @Test func aMoveForATimingOptionKeepsAPause() async throws {
        let harness = OptionsHarness()
        let session = try await harness.session()
        await session.pause()
        var options = session.options
        options.audioDelay = 0.5
        try await session.setOptions(options)
        #expect(harness.engine.kind == .mpv)
        #expect(session.isPaused)
    }

    @Test func aMovedSessionStaysOnMpvForTrackChanges() async throws {
        var source = OptionsHarness.source()
        var other = MediaStreamInfo(index: 2, kind: .audio)
        other.codec = "aac"
        source.streams.append(other)
        let harness = OptionsHarness()
        let session = try await harness.session(sources: [source])
        var options = session.options
        options.subtitleDelay = 1
        try await session.setOptions(options)

        try await session.selectAudioTrack(id: 2)

        #expect(harness.engine.kind == .mpv)
        #expect(harness.engine.applied.last?.subtitleDelay == 1)
    }

    @Test func zeroingATimingOptionDoesNotMoveEngines() async throws {
        let harness = OptionsHarness()
        let session = try await harness.session()
        var options = session.options
        options.audioDelay = 0
        try await session.setOptions(options)
        #expect(harness.engines.count == 1)
    }

    @Test func timingOptionsAreDisabledWithAReasonOnATranscode() async throws {
        var source = OptionsHarness.source()
        source.supportsDirectPlay = false
        let harness = OptionsHarness()
        let session = try await harness.session(sources: [source])
        #expect(session.route?.method == .transcode)
        guard case .unavailable(let reason) = session.availability(of: .audioDelay) else {
            Issue.record("Should be unavailable")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test func timingOptionsAreDisabledWhenMpvCantPlayIt() async throws {
        var source = OptionsHarness.source()
        source.streams[0].codec = "prores"
        source.container = "mp4"
        let harness = OptionsHarness()
        let session = try await harness.session(sources: [source])
        #expect(session.route?.method == .transcode)
        if case .available = session.availability(of: .subtitleDelay) {
            Issue.record("Should not be available")
        }
    }

    @Test func subtitlesLiftOverTheUsersOwnPositionAndComeBack() async throws {
        let harness = OptionsHarness()
        var options = PlaybackOptions()
        options.subtitleRaise = 10
        let session = try await harness.session(options: options)

        session.setLiftsSubtitles(true)
        #expect(harness.engine.applied.last?.subtitleRaise ?? 0 > 10)
        #expect(session.options.subtitleRaise == 10)

        session.setLiftsSubtitles(false)
        #expect(harness.engine.applied.last?.subtitleRaise == 10)
    }

    @Test func aMoveWhileLiftedStaysLifted() async throws {
        let harness = OptionsHarness()
        let session = try await harness.session()
        session.setLiftsSubtitles(true)
        var options = session.options
        options.audioDelay = 1
        try await session.setOptions(options)
        #expect(harness.engine.kind == .mpv)
        #expect(harness.engine.applied.last?.subtitleRaise ?? 0 > 0)
    }

    // MARK: Quality

    @Test func aLimitBelowTheFileMovesToATranscodeAtTheSamePosition() async throws {
        let harness = OptionsHarness()
        let session = try await harness.session()
        harness.engine.position = Ticks(seconds: 200)

        try await session.setQuality(maxBitrate: 2_000_000, sourceID: nil)

        #expect(session.route?.method == .transcode)
        #expect(harness.engine.kind == .avPlayer)
        #expect(harness.engine.loaded?.startPosition == Ticks(seconds: 200))
        #expect(await harness.client.playbackInfoRequests.last?.maxStreamingBitrate == 2_000_000)
        #expect(await harness.client.playbackInfoRequests.last?.startPosition == Ticks(seconds: 200))
    }

    @Test func aLimitAboveTheFileStaysDirect() async throws {
        let harness = OptionsHarness()
        let session = try await harness.session()
        try await session.setQuality(maxBitrate: 40_000_000, sourceID: nil)
        #expect(session.route?.method == .directPlay)
    }

    @Test func removingTheLimitGoesBackToDirectAndEndsTheTranscode() async throws {
        let harness = OptionsHarness()
        let session = try await harness.session(maxBitrate: 2_000_000)
        #expect(session.route?.method == .transcode)
        let source = OptionsHarness.source()
        await harness.client.configure {
            $0.playbackInfoValue = PlaybackInfo(playSessionID: "second", mediaSources: [source])
        }

        try await session.setQuality(maxBitrate: nil, sourceID: nil)

        #expect(session.route?.method == .directPlay)
        #expect(session.maxBitrate == nil)
        #expect(await harness.client.stoppedTranscodes == ["session"])
    }

    @Test func aRefusedLimitKeepsPlayingWhatWasPlaying() async throws {
        let harness = OptionsHarness()
        let session = try await harness.session()
        await harness.client.configure { $0.failure = .server(status: 500) }

        await #expect(throws: (any Error).self) {
            try await session.setQuality(maxBitrate: 2_000_000, sourceID: nil)
        }

        #expect(session.maxBitrate == nil)
        #expect(harness.engines.count == 1)
        #expect(!harness.engine.stopped)
    }

    @Test func aChosenVersionPlaysFirstAndGoesToTheServer() async throws {
        let sources = [OptionsHarness.source(id: "first"), OptionsHarness.source(id: "second")]
        let harness = OptionsHarness()
        let session = try await harness.session(sources: sources)
        #expect(session.route?.mediaSourceID == "first")

        try await session.setQuality(maxBitrate: nil, sourceID: "second")

        #expect(session.route?.mediaSourceID == "second")
        #expect(await harness.client.playbackInfoRequests.last?.mediaSourceID == "second")
        #expect(session.currentSource?.id == "second")
    }
}

@Suite struct PlayerPreferenceStoreTests {
    private func store() -> PlayerPreferenceStore {
        PlayerPreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    @Test func defaultsWhenNothingIsSaved() {
        #expect(store().load(userID: "a") == PlayerPreferences())
    }

    @Test func eachUserKeepsTheirOwn() {
        let store = store()
        var first = PlayerPreferences()
        first.subtitleScale = 1.5
        first.subtitleRaise = 10
        first.pictureMode = .fill
        first.maxBitrate = 8_000_000
        store.save(first, userID: "a")

        #expect(store.load(userID: "a") == first)
        #expect(store.load(userID: "b") == PlayerPreferences())
    }
}

@Suite struct PlayerInfoTests {
    private func source() -> PlaybackMediaSource {
        var source = PlaybackMediaSource(id: "source")
        source.container = "mkv"
        source.bitRate = 12_500_000
        source.size = 1_000_000_000
        var video = MediaStreamInfo(index: 0, kind: .video)
        video.codec = "hevc"
        video.width = 3840
        video.height = 2160
        video.frameRate = 23.976
        video.bitDepth = 10
        video.videoRangeType = "HDR10"
        var audio = MediaStreamInfo(index: 1, kind: .audio)
        audio.displayTitle = "English TrueHD"
        var subtitle = MediaStreamInfo(index: 2, kind: .subtitle)
        subtitle.displayTitle = "English PGS"
        source.streams = [video, audio, subtitle]
        return source
    }

    private func route(_ engine: PlaybackEngineKind, _ method: PlayMethod) -> PlaybackRoute {
        PlaybackRoute(engine: engine, method: method, url: URL(string: "http://server.invalid")!, mediaSourceID: "source")
    }

    private func value(_ rows: [PlayerInfo.Row], _ title: String) -> String? {
        rows.first { $0.title == title }?.value
    }

    @Test func describesWhatIsPlaying() {
        let rows = PlayerInfo.rows(source: source(), route: route(.mpv, .directPlay), audioIndex: 1, subtitleIndex: 2)
        #expect(value(rows, "Player") == "mpv")
        #expect(value(rows, "Playing") == "Direct from the file")
        #expect(value(rows, "Video") == "HEVC, 3840 x 2160, 24 fps, 10-bit")
        #expect(value(rows, "Dynamic range") == "HDR10")
        #expect(value(rows, "Audio") == "English TrueHD")
        #expect(value(rows, "Subtitles") == "English PGS")
        #expect(value(rows, "Container") == "mkv")
        #expect(value(rows, "Bitrate") == "12.5 Mbps")
        #expect(value(rows, "File size") != nil)
    }

    @Test func aTranscodeAndNoSubtitlesSaySo() {
        let rows = PlayerInfo.rows(source: source(), route: route(.avPlayer, .transcode), audioIndex: 1, subtitleIndex: nil)
        #expect(value(rows, "Player") == "AVPlayer")
        #expect(value(rows, "Playing") == "Converted by the server")
        #expect(value(rows, "Subtitles") == "Off")
    }

    @Test func missingDetailsLeaveNoEmptyRows() {
        let rows = PlayerInfo.rows(source: nil, route: nil, audioIndex: nil, subtitleIndex: nil)
        #expect(rows.allSatisfy { !$0.value.isEmpty })
        #expect(value(rows, "Video") == nil)
    }
}

@MainActor
@Suite struct SystemCaptionStyleTests {
    private func stream(_ index: Int, _ language: String?, title: String? = nil, forced: Bool = false) -> MediaStreamInfo {
        var stream = MediaStreamInfo(index: index, kind: .subtitle)
        stream.language = language
        stream.displayTitle = title
        stream.isForced = forced
        return stream
    }

    private func style(alwaysOn: Bool = true, sdh: Bool = false) -> SystemCaptionStyle {
        var style = SystemCaptionStyle()
        style.isAlwaysOn = alwaysOn
        style.prefersSDH = sdh
        return style
    }

    @Test func nothingIsChosenUnlessCaptionsAreAlwaysOn() {
        #expect(style(alwaysOn: false).defaultSubtitle(in: [stream(2, "eng")], languages: ["en-AU"]) == nil)
    }

    @Test func aPlainTrackInThePersonsLanguageIsChosen() {
        let tracks = [stream(2, "fre"), stream(3, "eng", title: "English SDH"), stream(4, "eng", title: "English")]
        #expect(style().defaultSubtitle(in: tracks, languages: ["en-AU"]) == 4)
    }

    @Test func aPreferenceForSDHChoosesThatTrack() {
        let tracks = [stream(4, "eng", title: "English"), stream(3, "eng", title: "English SDH")]
        #expect(style(sdh: true).defaultSubtitle(in: tracks, languages: ["en-AU"]) == 3)
    }

    @Test func eachFallsBackToTheOtherKind() {
        #expect(style(sdh: true).defaultSubtitle(in: [stream(4, "eng", title: "English")], languages: ["en"]) == 4)
        #expect(style().defaultSubtitle(in: [stream(3, "eng", title: "English [CC]")], languages: ["en"]) == 3)
    }

    @Test func forcedTracksAndOtherLanguagesAreNotChosen() {
        let tracks = [stream(2, "eng", title: "English Forced", forced: true), stream(3, "fre")]
        #expect(style().defaultSubtitle(in: tracks, languages: ["en"]) == nil)
    }

    @Test func alwaysOnTurnsSubtitlesOnWhenTheServerChoseNothing() async throws {
        var source = OptionsHarness.source()
        source.streams.append(stream(2, "eng", title: "English"))
        let harness = OptionsHarness()
        let session = try await harness.session(sources: [source], captions: style())
        #expect(session.route?.subtitleStreamIndex == 2)
    }

    @Test func theServersChoiceBeatsAlwaysOn() async throws {
        var source = OptionsHarness.source()
        source.streams.append(stream(2, "eng", title: "English"))
        source.streams.append(stream(3, "eng", title: "English Commentary"))
        source.defaultSubtitleStreamIndex = 3
        let harness = OptionsHarness()
        let session = try await harness.session(sources: [source], captions: style())
        #expect(session.route?.subtitleStreamIndex == 3)
    }
}
