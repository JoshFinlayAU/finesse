import Foundation
import Testing
@testable import FinEsse

/// What happens when things arrive during an await. The gates hold a call open so that stop or a
/// second track pick really does land in the middle, as it can on a real network.
@MainActor
@Suite struct PlaybackLifecycleTests {
    private func stream(_ index: Int, _ kind: MediaStreamKind, _ codec: String) -> MediaStreamInfo {
        var info = MediaStreamInfo(index: index, kind: kind)
        info.codec = codec
        return info
    }

    private func makeInfo(defaultAudio: Int? = nil, session: String = "first") -> PlaybackInfo {
        var source = PlaybackMediaSource(id: "source")
        source.container = "mp4"
        source.supportsDirectPlay = true
        source.directPlayURL = URL(string: "http://server.invalid/direct")
        source.defaultAudioStreamIndex = defaultAudio
        source.streams = [
            stream(0, .video, "h264"),
            stream(1, .audio, "aac"),
            stream(2, .audio, "ac3"),
            stream(3, .audio, "ac3"),
        ]
        return PlaybackInfo(playSessionID: session, mediaSources: [source])
    }

    private func makeClient(_ info: PlaybackInfo) async throws -> InMemoryJellyfinClient {
        let client = InMemoryJellyfinClient()
        _ = try await client.signIn(username: "Test User", password: "password")
        await client.configure { $0.playbackInfoValue = info }
        return client
    }

    private func makeSession(
        _ client: InMemoryJellyfinClient,
        configure: @escaping @MainActor (FakePlaybackEngine) -> Void = { _ in }
    ) -> (PlaybackSession, () -> [FakePlaybackEngine]) {
        var engines: [FakePlaybackEngine] = []
        let session = PlaybackSession(client: client, itemID: "item") { kind in
            let engine = FakePlaybackEngine(kind: kind)
            configure(engine)
            engines.append(engine)
            return engine
        }
        return (session, { engines })
    }

    // MARK: Finding 1: stop during start

    @Test func stopDuringPlaybackInfoNeverStartsAnEngine() async throws {
        let client = try await makeClient(makeInfo())
        let gate = TestGate()
        await client.configure { $0.playbackInfoGate = { await gate.pass() } }
        let (session, engines) = makeSession(client)

        let starting = Task { try await session.start() }
        await gate.waitForArrival()
        await session.stop()
        await gate.open()
        try await starting.value

        #expect(engines().isEmpty, "Nothing should be left playing after Back")
        #expect(session.engine == nil)
        #expect(await client.startReports.isEmpty)
    }

    @Test func stopDuringTheAudioCheckStopsTheEngineAndStartsNoOther() async throws {
        let client = try await makeClient(makeInfo(defaultAudio: 2))
        let gate = TestGate()
        let (session, engines) = makeSession(client) { engine in
            if engine.kind == .avPlayer {
                engine.unreachableAudio = [2]
                engine.canSelectGate = gate
            }
        }

        let starting = Task { try await session.start() }
        await gate.waitForArrival()
        await session.stop()
        await gate.open()
        try await starting.value

        #expect(engines().map(\.kind) == [.avPlayer])
        #expect(engines().allSatisfy { $0.stopped })
        #expect(session.engine == nil)
        #expect(await client.startReports.isEmpty)
    }

    // MARK: Finding 7: stop during the start report

    @Test func stopDuringTheStartReportWaitsSoStartReachesTheServerFirst() async throws {
        let client = try await makeClient(makeInfo())
        let gate = TestGate()
        await client.configure { $0.reportStartGate = { await gate.pass() } }
        let (session, engines) = makeSession(client)

        let starting = Task { try await session.start() }
        await gate.waitForArrival()
        let stopping = Task { await session.stop() }
        await letOtherTasksRun()
        #expect(await client.stopReports.isEmpty, "Stop must not overtake Start")

        await gate.open()
        try await starting.value
        await stopping.value

        #expect(await client.startReports.count == 1)
        #expect(await client.stopReports.count == 1)
        #expect(engines().allSatisfy { $0.stopped })
    }

    // MARK: Finding 1: track changes

    @Test func stopDuringATrackChangeStartsNoNewEngine() async throws {
        let client = try await makeClient(makeInfo())
        let gate = TestGate()
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].unreachableAudio = [2]
        engines()[0].canSelectGate = gate

        let changing = Task { try await session.selectAudioTrack(id: 2) }
        await gate.waitForArrival()
        await session.stop()
        await gate.open()
        try await changing.value

        #expect(engines().count == 1, "No engine should start after stop")
        #expect(engines().allSatisfy { $0.stopped })
        #expect(session.engine == nil)
    }

    @Test func twoQuickTrackPicksLeaveOneLiveEngineWithTheLastChoice() async throws {
        let client = try await makeClient(makeInfo())
        let gate = TestGate()
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].unreachableAudio = [2, 3]
        engines()[0].canSelectGate = gate

        let first = Task { try await session.selectAudioTrack(id: 2) }
        await gate.waitForArrival()
        let second = Task { try await session.selectAudioTrack(id: 3) }
        await letOtherTasksRun()
        await gate.open()
        try await first.value
        try await second.value

        let live = engines().filter { !$0.stopped }
        #expect(live.count == 1, "An orphaned engine would keep playing")
        #expect(live.first === session.engine)
        #expect(session.engine?.selectedAudioTrackID == 3)
        #expect(session.route?.audioStreamIndex == 3)
        #expect(session.route?.engine == session.engine?.kind)
        await session.stop()
    }

    @Test func aSecondPickUsesTheFirstPicksResult() async throws {
        let client = try await makeClient(makeInfo())
        let gate = TestGate()
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].canSelectGate = gate

        let audio = Task { try await session.selectAudioTrack(id: 2) }
        await gate.waitForArrival()
        let subtitles = Task { try await session.selectSubtitleTrack(id: nil) }
        await letOtherTasksRun()
        await gate.open()
        try await audio.value
        try await subtitles.value

        #expect(session.engine?.selectedAudioTrackID == 2, "The subtitle pick must not undo the audio pick")
        await session.stop()
    }

    @Test func recoveryAfterStopDoesNothing() async throws {
        let client = try await makeClient(makeInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        await session.stop()
        #expect(!(await session.recoverFromEngineFailure()))
        #expect(engines().count == 1)
    }

    // MARK: Finding 3: the reporter's play session

    @Test func reportsAfterATranscodeTrackChangeNameTheNewPlaySession() async throws {
        var info = makeInfo(session: "first")
        info.mediaSources[0].supportsDirectPlay = false
        info.mediaSources[0].supportsTranscoding = true
        info.mediaSources[0].transcodingURL = URL(string: "http://server.invalid/first.m3u8")
        let client = try await makeClient(info)
        let (session, _) = makeSession(client)
        try await session.start()
        #expect(await client.startReports.first?.playSessionID == "first")

        info.playSessionID = "second"
        info.mediaSources[0].transcodingURL = URL(string: "http://server.invalid/second.m3u8")
        let next = info
        await client.configure { $0.playbackInfoValue = next }
        try await session.selectAudioTrack(id: 2)

        #expect(await client.progressReports.last?.playSessionID == "second")
        await session.stop()
        #expect(await client.stopReports.first?.playSessionID == "second")
    }

    // MARK: Staying paused across a move between engines

    /// Starts on mpv only because of the default PGS subtitle, so turning it off moves to AVPlayer.
    private func makeSubtitleInfo() -> PlaybackInfo {
        var info = makeInfo()
        info.mediaSources[0].streams.append(stream(4, .subtitle, "pgssub"))
        info.mediaSources[0].defaultSubtitleStreamIndex = 4
        return info
    }

    private func expectPaused(
        _ session: PlaybackSession,
        _ engine: FakePlaybackEngine,
        at position: Double,
        client: InMemoryJellyfinClient,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        #expect(session.engine === engine, sourceLocation: sourceLocation)
        #expect(engine.loaded?.startPosition == Ticks(seconds: position), sourceLocation: sourceLocation)
        #expect(session.isPaused, "Paused straight after the move", sourceLocation: sourceLocation)
        #expect(await client.progressReports.last?.isPaused == true, sourceLocation: sourceLocation)
        engine.settle()
        #expect(engine.state == .paused, "The new engine must not start playing", sourceLocation: sourceLocation)
        #expect(session.isPaused, sourceLocation: sourceLocation)
    }

    @Test func aPausedPickMovingFromAVPlayerToMpvStaysPaused() async throws {
        let client = try await makeClient(makeInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].settle()
        engines()[0].unreachableAudio = [2]
        await session.pause()
        engines()[0].settle()
        engines()[0].position = Ticks(seconds: 100)

        try await session.selectAudioTrack(id: 2)

        #expect(engines().map(\.kind) == [.avPlayer, .mpv])
        await expectPaused(session, engines()[1], at: 100, client: client)
        await session.stop()
    }

    @Test func aPausedPickMovingFromMpvToAVPlayerStaysPaused() async throws {
        let client = try await makeClient(makeSubtitleInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        #expect(engines().map(\.kind) == [.mpv])
        engines()[0].settle()
        await session.pause()
        engines()[0].settle()
        engines()[0].position = Ticks(seconds: 100)

        try await session.selectSubtitleTrack(id: nil)

        #expect(engines().map(\.kind) == [.mpv, .avPlayer])
        await expectPaused(session, engines()[1], at: 100, client: client)
        await session.stop()
    }

    @Test func aMoveWhileThePauseIsStillCatchingUpStaysPaused() async throws {
        let client = try await makeClient(makeInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].settle()
        engines()[0].unreachableAudio = [2]
        await session.pause()
        #expect(engines()[0].state == .playing, "The pause hasn't landed yet")
        engines()[0].position = Ticks(seconds: 100)

        try await session.selectAudioTrack(id: 2)

        await expectPaused(session, engines()[1], at: 100, client: client)
        await session.stop()
    }

    @Test func aMoveThroughAnEngineThatCannotReachTheAudioStaysPaused() async throws {
        var info = makeSubtitleInfo()
        info.mediaSources[0].defaultAudioStreamIndex = 2
        let client = try await makeClient(info)
        let (session, engines) = makeSession(client) { engine in
            engine.unreachableAudio = engine.kind == .avPlayer ? [2] : []
        }
        try await session.start()
        engines()[0].settle()
        await session.pause()
        engines()[0].settle()
        engines()[0].position = Ticks(seconds: 100)

        try await session.selectSubtitleTrack(id: nil)

        #expect(engines().map(\.kind) == [.mpv, .avPlayer, .mpv])
        await expectPaused(session, engines()[2], at: 100, client: client)
        await session.stop()
    }

    @Test func anEngineFailingWhilePausedMovesAndStaysPaused() async throws {
        let client = try await makeClient(makeInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].settle()
        await session.pause()
        engines()[0].settle()
        #expect(session.isPaused)
        engines()[0].position = Ticks(seconds: 100)
        engines()[0].state = .failed("broken")

        #expect(await session.recoverFromEngineFailure())

        await letOtherTasksRun()
        await expectPaused(session, engines()[1], at: 100, client: client)
        await session.stop()
    }

    @Test func aRebuiltTranscodeStaysPaused() async throws {
        var info = makeInfo(session: "first")
        info.mediaSources[0].supportsDirectPlay = false
        info.mediaSources[0].supportsTranscoding = true
        info.mediaSources[0].transcodingURL = URL(string: "http://server.invalid/first.m3u8")
        let client = try await makeClient(info)
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].settle()
        await session.pause()
        engines()[0].settle()
        engines()[0].position = Ticks(seconds: 100)

        info.mediaSources[0].transcodingURL = URL(string: "http://server.invalid/second.m3u8")
        let next = info
        await client.configure { $0.playbackInfoValue = next }
        try await session.selectAudioTrack(id: 2)

        #expect(engines().count == 2)
        await expectPaused(session, engines()[1], at: 100, client: client)
        await session.stop()
    }

    @Test func resumingAfterAMoveLastsThroughTheNextMove() async throws {
        let client = try await makeClient(makeInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].settle()
        engines()[0].unreachableAudio = [2]
        await session.pause()
        engines()[0].settle()
        try await session.selectAudioTrack(id: 2)
        engines()[1].settle()
        #expect(engines()[1].state == .paused)

        await session.play()
        engines()[1].settle()
        #expect(engines()[1].state == .playing)
        #expect(!session.isPaused)

        engines()[1].state = .failed("broken")
        #expect(!(await session.recoverFromEngineFailure()), "AVPlayer can't reach this audio")
        await session.stop()
    }

    @Test func aMoveWhilePlayingKeepsPlaying() async throws {
        let client = try await makeClient(makeInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].settle()
        engines()[0].unreachableAudio = [2]

        try await session.selectAudioTrack(id: 2)

        #expect(!session.isPaused)
        #expect(await client.progressReports.last?.isPaused == false)
        engines()[1].settle()
        #expect(engines()[1].state == .playing)
        await session.stop()
    }

    @Test func playingBeforeAMoveClearsAnEarlierPause() async throws {
        let client = try await makeClient(makeInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].settle()
        engines()[0].unreachableAudio = [2]
        await session.pause()
        engines()[0].settle()
        await session.play()
        engines()[0].settle()

        try await session.selectAudioTrack(id: 2)

        engines()[1].settle()
        #expect(engines()[1].state == .playing)
        await session.stop()
    }

    // MARK: Ending the old transcode

    private func transcodeInfo(session: String) -> PlaybackInfo {
        var info = makeInfo(session: session)
        info.mediaSources[0].supportsDirectPlay = false
        info.mediaSources[0].supportsTranscoding = true
        info.mediaSources[0].transcodingURL = URL(string: "http://server.invalid/\(session).m3u8")
        return info
    }

    @Test func aTranscodeTrackChangeEndsTheOldJobAfterTheNewOneIsUp() async throws {
        let client = try await makeClient(transcodeInfo(session: "first"))
        let (session, engines) = makeSession(client)
        try await session.start()

        let next = transcodeInfo(session: "second")
        await client.configure { $0.playbackInfoValue = next }
        try await session.selectAudioTrack(id: 2)

        #expect(engines().count == 2)
        #expect(engines()[0].stopped, "The old stream goes first, or ending its job looks like a failure")
        #expect(await client.stoppedTranscodes == ["first"])
        await session.stop()
        #expect(await client.stoppedTranscodes == ["first"], "Stop itself ends the current job")
        #expect(await client.stopReports.first?.playSessionID == "second")
    }

    /// The server ends the job when told to stop. An engine still running then asks for its next
    /// segment, which starts a new job that nothing ends.
    @Test func theEngineStopsBeforeTheServerIsTold() async throws {
        let client = try await makeClient(transcodeInfo(session: "first"))
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].position = Ticks(seconds: 77)
        let gate = TestGate()
        await client.configure { $0.reportStoppedGate = { await gate.pass() } }

        let stopping = Task { await session.stop() }
        await gate.waitForArrival()

        #expect(engines()[0].stopped, "The stream must be gone by the time the server hears")
        await gate.open()
        await stopping.value
        #expect(await client.stopReports.first?.position == Ticks(seconds: 77), "The final position still goes")
        #expect(session.engine == nil)
    }

    @Test func aDirectPlayTrackChangeEndsNoTranscode() async throws {
        let client = try await makeClient(makeInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].unreachableAudio = [2]
        try await session.selectAudioTrack(id: 2)
        #expect(await client.stoppedTranscodes.isEmpty)
        await session.stop()
    }

    // MARK: Finding 6: pause and resume against an asynchronous engine

    @Test func pauseIsReportedAsPausedBeforeTheEngineCatchesUp() async throws {
        let client = try await makeClient(makeInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        engines()[0].settle()
        #expect(engines()[0].state == .playing)

        await session.pause()

        #expect(engines()[0].state == .playing, "The fake should still be catching up")
        await letOtherTasksRun()
        #expect(await client.progressReports.last?.isPaused == true)
        await session.stop()
    }

    @Test func resumeIsReportedAsPlayingBeforeTheEngineCatchesUp() async throws {
        let client = try await makeClient(makeInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        await session.pause()
        engines()[0].settle()
        #expect(engines()[0].state == .paused)

        await session.play()

        #expect(engines()[0].state == .paused, "The fake should still be catching up")
        await letOtherTasksRun()
        #expect(await client.progressReports.last?.isPaused == false)
        await session.stop()
    }

    @Test func aPauseTheEngineDidItselfIsStillReported() async throws {
        let client = try await makeClient(makeInfo())
        let (session, engines) = makeSession(client)
        try await session.start()
        await session.pause()
        engines()[0].settle()
        await session.play()
        engines()[0].settle()
        // The player reads this several times a second, which is what ends the request.
        #expect(!session.isPaused)

        engines()[0].state = .paused
        await session.seek(to: Ticks(seconds: 10))

        await letOtherTasksRun()
        #expect(await client.progressReports.last?.isPaused == true)
        await session.stop()
    }
}

/// Serialized because these count every live mpv core in the process.
@MainActor
@Suite(.serialized) struct MPVEngineShutdownTests {
    @Test func droppingAnEngineWithoutStoppingItShutsMpvDown() async throws {
        let before = MPVEngine.liveCoreCount
        var engine: MPVEngine? = MPVEngine()
        #expect(MPVEngine.liveCoreCount == before + 1)
        _ = engine
        engine = nil

        let deadline = ContinuousClock.now + .seconds(5)
        while MPVEngine.liveCoreCount > before, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(MPVEngine.liveCoreCount == before, "mpv's thread and audio would run until the app dies")
    }

    @Test func stoppingThenDroppingAnEngineIsSafe() async throws {
        let before = MPVEngine.liveCoreCount
        var engine: MPVEngine? = MPVEngine()
        engine?.stop()
        engine?.stop()
        engine?.pause()
        engine?.seek(to: Ticks(seconds: 1))
        _ = engine?.activeAudioTrackID
        engine = nil

        let deadline = ContinuousClock.now + .seconds(5)
        while MPVEngine.liveCoreCount > before, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(MPVEngine.liveCoreCount == before)
    }
}
