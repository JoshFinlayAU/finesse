import Foundation
import Observation
import Testing
import UIKit
@testable import FinEsse

private typealias FakeEngine = FakePlaybackEngine

@MainActor
private final class Harness {
    let client = InMemoryJellyfinClient()
    var engines: [FakeEngine] = []
    var startedWhileCancelled = false
    var date = Date(timeIntervalSince1970: 0)
    let model: PlayerModel

    var engine: FakeEngine { engines[engines.count - 1] }

    init(
        item: MediaItem,
        resume: Ticks? = nil,
        store: PlayerPreferenceStore = PlayerPreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
        captions: SystemCaptionStyle = SystemCaptionStyle()
    ) {
        var factory: PlaybackSession.EngineFactory = { _ in fatalError("set below") }
        var made: (FakeEngine) -> Void = { _ in }
        factory = { kind in
            let engine = FakeEngine(kind: kind)
            made(engine)
            return engine
        }
        var clock: () -> Date = { .now }
        model = PlayerModel(
            client: client,
            request: PlaybackRequest(item: item, resumePosition: resume),
            now: { clock() },
            preferenceStore: store,
            captionStyle: captions,
            makeEngine: factory
        )
        made = { [unowned self] in
            engines.append($0)
            if Task.isCancelled { startedWhileCancelled = true }
        }
        clock = { [unowned self] in date }
    }

    func prepare(segments: [MediaSegment] = [], next: MediaItem? = nil) async throws {
        _ = try await client.signIn(username: "Test User", password: "password")
        var source = PlaybackMediaSource(id: "source")
        source.container = "mp4"
        source.supportsDirectPlay = true
        source.directPlayURL = URL(string: "http://server.invalid/direct")
        var video = MediaStreamInfo(index: 0, kind: .video)
        video.codec = "h264"
        var audio = MediaStreamInfo(index: 1, kind: .audio)
        audio.codec = "aac"
        var pgs = MediaStreamInfo(index: 2, kind: .subtitle)
        pgs.codec = "pgssub"
        source.streams = [video, audio, pgs]
        let info = PlaybackInfo(playSessionID: "session", mediaSources: [source])
        let itemID = model.item.id
        await client.configure {
            $0.playbackInfoValue = info
            $0.segments = [itemID: segments]
            $0.nextUpValue = next.map { [$0] } ?? []
        }
    }
}

@MainActor
@Suite struct PlayerModelTests {
    private func episode(_ id: String = "episode", series: String? = "series") -> MediaItem {
        var item = MediaItem(id: id, name: id, kind: .episode)
        item.seriesID = series
        item.runTime = Ticks(seconds: 1000)
        return item
    }

    private func segment(_ kind: MediaSegmentKind, _ start: Double, _ end: Double, id: String = "s") -> MediaSegment {
        MediaSegment(id: id, itemID: "episode", kind: kind, start: Ticks(seconds: start), end: Ticks(seconds: end))
    }

    @Test func startsAtResumePositionAndReportsIt() async throws {
        let harness = Harness(item: episode(), resume: Ticks(seconds: 300))
        try await harness.prepare()
        await harness.model.start()
        #expect(harness.model.phase == .playing)
        #expect(harness.engine.loaded?.startPosition == Ticks(seconds: 300))
        #expect(await harness.client.startReports.first?.position == Ticks(seconds: 300))
        await harness.model.exit()
    }

    @Test func nilResumeStartsFromTheBeginning() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()
        #expect(harness.engine.loaded?.startPosition == .zero)
        await harness.model.exit()
    }

    @Test func failureToStartShowsAnError() async throws {
        let harness = Harness(item: episode())
        _ = try await harness.client.signIn(username: "Test User", password: "password")
        await harness.model.start()
        guard case .failed = harness.model.phase else {
            Issue.record("Expected failed, got \(harness.model.phase)")
            return
        }
    }

    @Test func avPlayerFailingMovesToMpvAtTheCurrentPositionWithNoError() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()
        harness.engine.position = Ticks(seconds: 300)
        harness.engine.state = .failed("broken")

        await harness.model.tick()

        #expect(harness.model.phase == .playing)
        #expect(harness.engines.map(\.kind) == [.avPlayer, .mpv])
        #expect(harness.engine.loaded?.startPosition == Ticks(seconds: 300))
        #expect(harness.model.engine?.kind == .mpv)
        #expect(await harness.client.stopReports.isEmpty)
        await harness.model.exit()
        #expect(await harness.client.stopReports.count == 1)
    }

    @Test func theErrorShowsOnlyWhenMpvFailsToo() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()
        harness.engine.state = .failed("first")
        await harness.model.tick()
        harness.engine.position = Ticks(seconds: 50)
        harness.engine.state = .failed("second")

        await harness.model.tick()

        #expect(harness.model.phase == .failed("second"))
        #expect(harness.engines.count == 2)
        #expect(await harness.client.stopReports.count == 1)
        #expect(await harness.client.stopReports.first?.position == Ticks(seconds: 50))
    }

    /// Finding 1: Back while the first load is still in flight.
    @Test func backDuringLoadLeavesNothingPlaying() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        let gate = TestGate()
        await harness.client.configure { $0.playbackInfoGate = { await gate.pass() } }
        let model = harness.model

        let starting = Task { await model.start() }
        await gate.waitForArrival()
        await harness.model.backPressed()
        await gate.open()
        await starting.value

        #expect(harness.model.phase == .finished, "Back must not be overwritten when the load returns")
        #expect(harness.engines.isEmpty)
    }

    /// Finding 1: autoplay's start runs in its own task, which nothing cancels.
    @Test func backDuringTheNextEpisodesLoadLeavesNothingPlaying() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare(next: episode("next"))
        await harness.model.start()
        harness.engine.state = .ended
        await harness.model.tick()
        let gate = TestGate()
        await harness.client.configure { $0.playbackInfoGate = { await gate.pass() } }
        let model = harness.model

        let playing = Task { await model.playNext() }
        await gate.waitForArrival()
        await harness.model.exit()
        await gate.open()
        await playing.value

        #expect(harness.model.phase == .finished)
        #expect(harness.engines.count == 1)
    }

    /// Finding 1: Try Again also runs in its own task.
    @Test func backDuringTryAgainLeavesNothingPlaying() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()
        harness.engine.state = .failed("first")
        await harness.model.tick()
        harness.engine.state = .failed("second")
        await harness.model.tick()
        let gate = TestGate()
        await harness.client.configure { $0.playbackInfoGate = { await gate.pass() } }
        let model = harness.model

        let retrying = Task { await model.start() }
        await gate.waitForArrival()
        await harness.model.backPressed()
        await gate.open()
        await retrying.value

        #expect(harness.model.phase == .finished)
        #expect(harness.engines.count == 2)
        #expect(harness.engines.allSatisfy { $0.stopped })
    }

    /// Finding 1: stop also has to stop what's already running when Back lands mid-start.
    @Test func exitWhileTheEndOfAnEpisodeIsHandledDoesNotShowUpNext() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare(next: episode("next"))
        await harness.model.start()
        harness.engine.state = .ended
        let model = harness.model
        let ticking = Task { await model.tick() }
        await model.exit()
        await ticking.value
        #expect(harness.model.phase == .finished)
    }

    /// Finding 2: Try Again carries on from where it failed.
    @Test func tryAgainResumesFromWherePlaybackFailed() async throws {
        let harness = Harness(item: episode(), resume: Ticks(seconds: 100))
        try await harness.prepare()
        await harness.model.start()
        harness.engine.state = .failed("first")
        await harness.model.tick()
        harness.engine.position = Ticks(seconds: 3600)
        harness.engine.state = .failed("second")
        await harness.model.tick()
        #expect(await harness.client.stopReports.last?.position == Ticks(seconds: 3600))

        await harness.model.start()

        #expect(harness.engine.loaded?.startPosition == Ticks(seconds: 3600))
        #expect(await harness.client.startReports.last?.position == Ticks(seconds: 3600))
        await harness.model.exit()
    }

    /// Finding 2: a failure before anything played keeps the original resume point.
    @Test func tryAgainAfterAFailedStartKeepsTheResumePoint() async throws {
        let harness = Harness(item: episode(), resume: Ticks(seconds: 100))
        _ = try await harness.client.signIn(username: "Test User", password: "password")
        await harness.model.start()
        guard case .failed = harness.model.phase else {
            Issue.record("Expected failed, got \(harness.model.phase)")
            return
        }
        try await harness.prepare()
        await harness.model.start()
        #expect(harness.engine.loaded?.startPosition == Ticks(seconds: 100))
        await harness.model.exit()
    }

    /// Finding 6: every tick has to read the pause state, or a pause the engine does itself is hidden.
    @Test func aPauseTheEngineDoesItselfShowsAfterATickEvenWithControlsHidden() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()
        harness.engine.settle()
        #expect(!harness.model.controls.isShowing)
        await harness.model.tick()

        harness.engine.state = .paused

        #expect(harness.model.isPaused)
        await harness.model.exit()
    }

    /// Finding 6: pressing play/pause twice quickly must not rely on the engine having caught up.
    @Test func togglingTwiceBeforeTheEngineCatchesUpEndsPlaying() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()
        harness.engine.settle()

        await harness.model.togglePlayPause()
        #expect(harness.model.isPaused)
        await harness.model.togglePlayPause()
        #expect(!harness.model.isPaused)
        harness.engine.settle()
        #expect(harness.engine.state == .playing)
        await harness.model.exit()
    }

    @Test func tryAgainAfterBothFailStartsFreshOnAVPlayer() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()
        harness.engine.state = .failed("first")
        await harness.model.tick()
        harness.engine.state = .failed("second")
        await harness.model.tick()

        await harness.model.start()

        #expect(harness.model.phase == .playing)
        #expect(harness.engine.kind == .avPlayer)
        await harness.model.exit()
    }

    @Test func backStepsOutThenReportsStopOnce() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()
        harness.engine.position = Ticks(seconds: 42)
        await harness.model.send(.swipeUp)

        await harness.model.backPressed()
        #expect(!harness.model.controls.isShowing)
        #expect(harness.model.phase == .playing)
        #expect(await harness.client.stopReports.isEmpty)

        await harness.model.backPressed()
        #expect(harness.model.phase == .finished)
        #expect(await harness.client.stopReports.count == 1)
        #expect(await harness.client.stopReports.first?.position == Ticks(seconds: 42))

        await harness.model.exit()
        #expect(await harness.client.stopReports.count == 1)
    }

    @Test func clickPausesAndBackRestoresWithoutSeeking() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()
        harness.engine.settle()

        await harness.model.send(.click)
        #expect(harness.model.isPaused)
        await harness.model.send(.moveRight)
        #expect(harness.model.scrubPosition == Ticks(seconds: 10))

        await harness.model.backPressed()
        #expect(harness.model.scrubPosition == nil)
        #expect(!harness.model.isPaused)
        #expect(harness.engine.seeks.isEmpty)
        await harness.model.exit()
    }

    @Test func clicksAddUpAndTheSecondClickCommitsOneSeekAndResumes() async throws {
        let harness = Harness(item: episode(), resume: Ticks(seconds: 100))
        try await harness.prepare()
        await harness.model.start()
        harness.engine.settle()

        await harness.model.send(.click)
        await harness.model.send(.moveRight)
        await harness.model.send(.moveRight)
        #expect(harness.model.displayPosition == Ticks(seconds: 120))
        #expect(harness.engine.seeks.isEmpty)

        await harness.model.send(.click)
        #expect(harness.engine.seeks == [Ticks(seconds: 120)])
        #expect(harness.model.scrubPosition == nil)
        #expect(!harness.model.isPaused)
        await letOtherTasksRun()
        #expect(await harness.client.progressReports.last?.position == Ticks(seconds: 120))
        await harness.model.exit()
    }

    @Test func leftAndRightDoNothingWhilePlaying() async throws {
        let harness = Harness(item: episode(), resume: Ticks(seconds: 100))
        try await harness.prepare()
        await harness.model.start()
        await harness.model.send(.moveRight)
        await harness.model.send(.moveLeft)
        await harness.model.send(.panned(0.5))
        #expect(harness.model.scrubPosition == nil)
        #expect(harness.engine.seeks.isEmpty)
        await harness.model.exit()
    }

    @Test func subtitlesLiftOnlyWhileTheControlsShow() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()

        await harness.model.send(.swipeUp)
        #expect(harness.engine.applied.last?.subtitleRaise ?? 0 > 0)

        await harness.model.send(.swipeDown)
        #expect(harness.engine.applied.last?.subtitleRaise == 0)
        await harness.model.exit()
    }

    @Test func barHidesAfterTimeoutUnlessPausedAndAPanelStaysOpen() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()
        harness.engine.settle()
        await harness.model.send(.swipeUp)

        harness.date += PlayerControls.hideAfter - 1
        await harness.model.tick()
        #expect(harness.model.controls.mode == .bar)

        await harness.model.send(.openPanel(.audio))
        harness.date += 60
        await harness.model.tick()
        #expect(harness.model.controls.panel == .audio)

        await harness.model.backPressed()
        await harness.model.tick()
        #expect(harness.model.controls.mode == .bar)

        harness.date += PlayerControls.hideAfter
        await harness.model.togglePlayPause()
        harness.engine.settle()
        await harness.model.tick()
        #expect(harness.model.controls.mode == .bar)

        await harness.model.togglePlayPause()
        harness.engine.settle()
        await harness.model.tick()
        #expect(harness.model.controls.mode == .hidden)
        await harness.model.exit()
    }

    @Test func skipAppearsOnlyInsideIntroAndCreditsAndSeeksToTheEnd() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare(segments: [
            segment(.intro, 10, 40, id: "intro"),
            segment(.recap, 50, 60, id: "recap"),
            segment(.outro, 900, 950, id: "outro"),
        ])
        await harness.model.start()

        harness.engine.position = Ticks(seconds: 5)
        await harness.model.tick()
        #expect(harness.model.skip == nil)

        harness.engine.position = Ticks(seconds: 10)
        await harness.model.tick()
        #expect(harness.model.skip?.title == "Skip Intro")

        harness.engine.position = Ticks(seconds: 55)
        await harness.model.tick()
        #expect(harness.model.skip == nil)

        harness.engine.position = Ticks(seconds: 910)
        await harness.model.tick()
        #expect(harness.model.skip?.title == "Skip Credits")

        harness.engine.position = Ticks(seconds: 20)
        await harness.model.tick()
        await harness.model.skipPressed()
        #expect(harness.engine.seeks == [Ticks(seconds: 40)])
        harness.engine.settle()
        #expect(harness.engine.state == .playing)

        // Scrubbing back into a skipped intro doesn't offer it again.
        harness.engine.position = Ticks(seconds: 20)
        await harness.model.tick()
        #expect(harness.model.skip == nil)
        await harness.model.exit()
    }

    @Test func noSegmentsMeansNoSkip() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()
        harness.engine.position = Ticks(seconds: 10)
        await harness.model.tick()
        #expect(harness.model.skip == nil)
        await harness.model.exit()
    }

    @Test func endOfEpisodeReportsStopThenCountsDownAndPlaysNext() async throws {
        let next = episode("next")
        let harness = Harness(item: episode())
        try await harness.prepare(next: next)
        await harness.model.start()
        harness.engine.position = Ticks(seconds: 1000)
        harness.engine.state = .ended

        await harness.model.tick()
        #expect(await harness.client.stopReports.first?.position == Ticks(seconds: 1000))
        #expect(harness.model.phase == .upNext(next, secondsLeft: PlayerModel.upNextSeconds))

        for _ in 1..<PlayerModel.upNextSeconds {
            await harness.model.upNextTick()
        }
        #expect(harness.model.phase == .upNext(next, secondsLeft: 1))

        await harness.model.upNextTick()
        #expect(harness.model.phase == .playing)
        #expect(harness.model.item.id == "next")
        #expect(harness.engines.count == 2)
        #expect(await harness.client.startReports.last?.itemID == "next")
        await harness.model.exit()
        #expect(await harness.client.stopReports.count == 2)
    }

    /// The view's countdown task is cancelled by the phase change that starts the next episode.
    @Test func theCountdownEndingDoesNotCancelTheNextEpisode() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare(next: episode("next"))
        await harness.model.start()
        harness.engine.state = .ended
        await harness.model.tick()
        for _ in 1..<PlayerModel.upNextSeconds {
            await harness.model.upNextTick()
        }

        let model = harness.model
        let countdown = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.upNextTick()
        }
        await countdown.value

        #expect(!harness.startedWhileCancelled)
        #expect(harness.model.phase == .playing)
        #expect(harness.model.item.id == "next")
        await harness.model.exit()
    }

    @Test func cancellingUpNextFinishesWithoutPlaying() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare(next: episode("next"))
        await harness.model.start()
        harness.engine.state = .ended
        await harness.model.tick()
        harness.model.cancelUpNext()
        #expect(harness.model.phase == .finished)
        #expect(harness.engines.count == 1)
    }

    @Test func nextEpisodeResumesFromItsOwnSavedPosition() async throws {
        var next = episode("next")
        next.userState.playbackPosition = Ticks(seconds: 77)
        let harness = Harness(item: episode())
        try await harness.prepare(next: next)
        await harness.model.start()
        harness.engine.state = .ended
        await harness.model.tick()
        await harness.model.playNext()
        #expect(harness.engine.loaded?.startPosition == Ticks(seconds: 77))
        await harness.model.exit()
    }

    @Test func aMovieEndsWithoutUpNext() async throws {
        var movie = MediaItem(id: "movie", name: "movie", kind: .movie)
        movie.runTime = Ticks(seconds: 1000)
        let harness = Harness(item: movie)
        try await harness.prepare(next: episode("next"))
        await harness.model.start()
        harness.engine.state = .ended
        await harness.model.tick()
        #expect(harness.model.phase == .finished)
    }

    @Test func nextUpReturningTheSameEpisodeEnds() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare(next: episode())
        await harness.model.start()
        harness.engine.state = .ended
        await harness.model.tick()
        #expect(harness.model.phase == .finished)
    }

    @Test func trackChoiceGoesThroughTheSession() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()
        harness.engine.position = Ticks(seconds: 60)

        await harness.model.selectSubtitleTrack(id: 2)

        #expect(harness.engines.map(\.kind) == [.avPlayer, .mpv])
        #expect(harness.engine.loaded?.startPosition == Ticks(seconds: 60))
        #expect(harness.model.engine?.selectedSubtitleTrackID == 2)
        await harness.model.exit()
    }

    @Test func timesFormatForTheBar() {
        #expect(PlayerTime.format(Ticks(seconds: 59)) == "0:59")
        #expect(PlayerTime.format(Ticks(seconds: 3725)) == "1:02:05")
    }
}

/// Every option in the player's panels, from the model down to the engine.
@MainActor
@Suite struct PlayerOptionsModelTests {
    private func episode(_ id: String, position: Double = 0) -> MediaItem {
        var item = MediaItem(id: id, name: id, kind: .episode)
        item.seriesID = "series"
        item.runTime = Ticks(seconds: 1000)
        item.userState.playbackPosition = Ticks(seconds: position)
        return item
    }

    private func harness(
        item: MediaItem? = nil,
        store: PlayerPreferenceStore? = nil,
        captions: SystemCaptionStyle = SystemCaptionStyle()
    ) async throws -> (Harness, PlayerModel) {
        let harness = Harness(
            item: item ?? episode("two"),
            store: store ?? PlayerPreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            captions: captions
        )
        try await harness.prepare()
        let series = [episode("one"), episode("two"), episode("three", position: 50)]
        await harness.client.configure {
            $0.allItems = series
            $0.chapters["two"] = [
                ItemChapter(index: 0, name: "Start", start: .zero),
                ItemChapter(index: 1, name: "Middle", start: Ticks(seconds: 500)),
            ]
        }
        await harness.model.start()
        return (harness, harness.model)
    }

    @Test func audioAndSubtitleSelectionReachTheEngine() async throws {
        let (harness, model) = try await harness()
        await model.selectAudioTrack(id: 1)
        #expect(harness.engine.selectedAudioTrackID == 1)
        await model.selectSubtitleTrack(id: nil)
        #expect(harness.engine.selectedSubtitleTrackID == nil)
        await model.exit()
    }

    @Test func speedAppliesButIsNotSaved() async throws {
        let store = PlayerPreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let (harness, model) = try await harness(store: store)
        await model.setRate(1.5)
        #expect(harness.engine.applied.last?.rate == 1.5)
        #expect(model.preferences == PlayerPreferences())
        await model.exit()
    }

    @Test func theSystemCaptionSizeAppliesUntilThePersonPicksTheirOwn() async throws {
        var style = SystemCaptionStyle()
        style.scale = 1.5
        style.textColor = SubtitleColor(red: 1, green: 1, blue: 0, alpha: 1)
        let (harness, model) = try await harness(captions: style)
        #expect(harness.engine.applied.last?.subtitleScale == 1.5)
        #expect(harness.engine.applied.last?.subtitleTextColor == style.textColor)
        #expect(model.preferences.subtitleScale == nil)

        await model.adjustSubtitleScale(by: 1)
        #expect(model.options.subtitleScale == 1.6)
        #expect(model.preferences.subtitleScale == 1.6)
        await model.exit()
    }

    @Test func aPickedSizeBeatsTheSystemsOnTheNextPlayback() async throws {
        let store = PlayerPreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        var saved = PlayerPreferences()
        saved.subtitleScale = 0.8
        let session = try await InMemoryJellyfinClient().signIn(username: "Test User", password: "password")
        store.save(saved, userID: session.user.id)
        var style = SystemCaptionStyle()
        style.scale = 1.5

        let (harness, model) = try await harness(store: store, captions: style)

        #expect(harness.engine.applied.last?.subtitleScale == 0.8)
        await model.exit()
    }

    @Test func anOutOfRangeSystemSizeStaysWithinOurLimits() async throws {
        var style = SystemCaptionStyle()
        style.scale = 4
        let (harness, model) = try await harness(captions: style)
        #expect(harness.engine.applied.last?.subtitleScale == PlaybackOptions.subtitleScales.upperBound)
        await model.exit()
    }

    @Test func pictureModeAppliesAndSticks() async throws {
        let (harness, model) = try await harness()
        await model.setPictureMode(.fill)
        #expect(harness.engine.applied.last?.pictureMode == .fill)
        #expect(model.preferences.pictureMode == .fill)
        await model.exit()
    }

    @Test func subtitleSizeStepsStopAtTheLimitsAndStick() async throws {
        let (harness, model) = try await harness()
        await model.adjustSubtitleScale(by: 2)
        #expect(harness.engine.applied.last?.subtitleScale == 1.2)
        #expect(model.preferences.subtitleScale == 1.2)
        await model.adjustSubtitleScale(by: 50)
        #expect(model.options.subtitleScale == PlaybackOptions.subtitleScales.upperBound)
        await model.adjustSubtitleScale(by: -50)
        #expect(model.options.subtitleScale == PlaybackOptions.subtitleScales.lowerBound)
        await model.exit()
    }

    @Test func subtitlePositionStepsStopAtTheLimitsAndStick() async throws {
        let (harness, model) = try await harness()
        await model.adjustSubtitleRaise(by: 2)
        #expect(harness.engine.applied.last?.subtitleRaise == 2 * PlayerModel.subtitleRaiseStep)
        #expect(model.preferences.subtitleRaise == 2 * PlayerModel.subtitleRaiseStep)
        await model.adjustSubtitleRaise(by: -9)
        #expect(model.options.subtitleRaise == 0)
        await model.adjustSubtitleRaise(by: 99)
        #expect(model.options.subtitleRaise == PlaybackOptions.subtitleRaises.upperBound)
        await model.exit()
    }

    @Test func delaysMoveToMpvStopAtTheLimitsAndAreNotSaved() async throws {
        let (harness, model) = try await harness()
        #expect(harness.engine.kind == .avPlayer)
        await model.adjustAudioDelay(by: 3)
        #expect(harness.engine.kind == .mpv)
        #expect(harness.engine.applied.last?.audioDelay == 0.3)
        await model.adjustSubtitleDelay(by: -2)
        #expect(harness.engine.applied.last?.subtitleDelay == -0.2)
        await model.adjustSubtitleDelay(by: -500)
        #expect(model.options.subtitleDelay == PlaybackOptions.delays.lowerBound)
        #expect(model.preferences == PlayerPreferences())
        await model.exit()
    }

    @Test func offsetsResetForTheNextEpisodeAndSpeedCarriesOn() async throws {
        let (harness, model) = try await harness()
        await model.setRate(1.25)
        await model.adjustAudioDelay(by: 3)
        await model.playEpisode(try #require(model.nextEpisode))
        #expect(harness.engine.applied.last?.rate == 1.25)
        #expect(harness.engine.applied.last?.audioDelay == 0)
        await model.exit()
    }

    @Test func savedPreferencesApplyWhenPlaybackStarts() async throws {
        let store = PlayerPreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        var saved = PlayerPreferences()
        saved.subtitleScale = 1.5
        saved.subtitleRaise = 10
        saved.pictureMode = .stretch
        saved.maxBitrate = 2_000_000
        let session = try await InMemoryJellyfinClient().signIn(username: "Test User", password: "password")
        store.save(saved, userID: session.user.id)

        let (harness, model) = try await harness(store: store)

        #expect(harness.engine.applied.last?.subtitleScale == 1.5)
        #expect(harness.engine.applied.last?.subtitleRaise == 10)
        #expect(harness.engine.applied.last?.pictureMode == .stretch)
        #expect(model.session?.maxBitrate == 2_000_000)
        await model.exit()
    }

    @Test func aQualityChoiceSticks() async throws {
        let (kept, model) = try await harness()
        defer { withExtendedLifetime(kept) {} }
        await model.setMaxBitrate(8_000_000)
        #expect(model.preferences.maxBitrate == 8_000_000)
        #expect(model.qualityNote != nil)
        await model.setMaxBitrate(nil)
        #expect(model.preferences.maxBitrate == nil)
        #expect(model.qualityNote == nil)
        await model.exit()
    }

    @Test func chaptersLoadAndChoosingOneSeeksAndHidesTheControls() async throws {
        let (harness, model) = try await harness()
        #expect(model.chapters.count == 2)
        #expect(model.panels.contains(.chapters))
        await model.send(.swipeUp)
        await model.send(.openPanel(.chapters))

        await model.selectChapter(model.chapters[1])

        #expect(harness.engine.seeks == [Ticks(seconds: 500)])
        #expect(model.controls.mode == .hidden)
        #expect(model.chapter(at: Ticks(seconds: 600))?.name == "Middle")
        await model.exit()
    }

    @Test func aMovieOffersNeitherChaptersItLacksNorEpisodes() async throws {
        var movie = MediaItem(id: "movie", name: "movie", kind: .movie)
        movie.runTime = Ticks(seconds: 1000)
        let (kept, model) = try await harness(item: movie)
        defer { withExtendedLifetime(kept) {} }
        #expect(model.episodes.isEmpty)
        #expect(model.previousEpisode == nil)
        #expect(model.nextEpisode == nil)
        #expect(!model.panels.contains(.episodes))
        #expect(!model.panels.contains(.chapters))
        #expect(model.panels.contains(.audio))
        #expect(model.panels.contains(.info))
        await model.exit()
    }

    @Test func previousAndNextFollowTheSeriesOrder() async throws {
        let (kept, model) = try await harness()
        defer { withExtendedLifetime(kept) {} }
        #expect(model.previousEpisode?.id == "one")
        #expect(model.nextEpisode?.id == "three")
        await model.exit()
    }

    @Test func anotherEpisodeReportsStopThenResumesFromItsOwnPosition() async throws {
        let (harness, model) = try await harness()
        harness.engine.position = Ticks(seconds: 42)
        let first = harness.engine

        await model.playEpisode(try #require(model.nextEpisode))

        #expect(first.stopped)
        #expect(await harness.client.stopReports.first?.position == Ticks(seconds: 42))
        #expect(model.item.id == "three")
        #expect(harness.engine.loaded?.startPosition == Ticks(seconds: 50))
        #expect(model.phase == .playing)
        #expect(model.controls.mode == .hidden)
        await model.exit()
    }

    @Test func goingBackResumesFromTheServersPositionNotTheOldList() async throws {
        let (harness, model) = try await harness()
        let first = try #require(model.previousEpisode)
        #expect(first.userState.playbackPosition == .zero)
        await harness.client.configure { $0.allItems[0].userState.playbackPosition = Ticks(seconds: 1200) }

        await model.playEpisode(first)

        #expect(harness.engine.loaded?.startPosition == Ticks(seconds: 1200))
        await model.exit()
    }

    /// The stop report can fail, so the server's answer can be older than what was just watched.
    @Test func goingBackNeverResumesEarlierThanWhereItWasLeft() async throws {
        let (harness, model) = try await harness()
        harness.engine.position = Ticks(seconds: 700)
        let left = model.item
        await model.playEpisode(try #require(model.nextEpisode))
        // What the server would hold if the stop report had been lost.
        await harness.client.configure { $0.allItems[1].userState.playbackPosition = Ticks(seconds: 30) }

        await model.playEpisode(left)

        #expect(harness.engine.loaded?.startPosition == Ticks(seconds: 700))
        await model.exit()
    }

    /// Finishing an episode clears its position on the server, and that one should start over.
    @Test func aFinishedEpisodeStartsFromTheBeginning() async throws {
        let (harness, model) = try await harness()
        harness.engine.position = Ticks(seconds: 990)
        let left = model.item
        await model.playEpisode(try #require(model.nextEpisode))
        await harness.client.configure {
            $0.allItems[1].userState.playbackPosition = .zero
            $0.allItems[1].userState.isPlayed = true
        }

        await model.playEpisode(left)

        #expect(harness.engine.loaded?.startPosition == .zero)
        await model.exit()
    }

    @Test func choosingTheCurrentEpisodeOnlyClosesThePanel() async throws {
        let (harness, model) = try await harness()
        harness.engine.position = Ticks(seconds: 400)
        await model.send(.swipeUp)
        await model.send(.openPanel(.episodes))

        await model.playEpisode(model.item)

        #expect(harness.engines.count == 1, "It should keep playing")
        #expect(!harness.engine.stopped)
        #expect(model.controls.mode == .hidden)
        await model.exit()
    }

    // MARK: Nothing waits on a report

    private func holdingReports(_ harness: Harness) async -> TestGate {
        let gate = TestGate()
        await harness.client.configure { $0.reportProgressGate = { await gate.pass() } }
        return gate
    }

    @Test(.timeLimit(.minutes(1))) func aCommittedScrubResumesWithoutWaitingForTheNetwork() async throws {
        let (harness, model) = try await harness()
        harness.engine.settle()
        let gate = await holdingReports(harness)

        let click = Task { await model.send(.click) }
        await letOtherTasksRun()
        harness.engine.settle()
        let move = Task { await model.send(.moveRight) }
        await letOtherTasksRun()
        let commit = Task { await model.send(.click) }
        await letOtherTasksRun()

        #expect(!model.isPaused, "Playback should resume while the report is out")
        #expect(harness.engine.seeks.count == 1)

        await gate.open()
        _ = await (click.value, move.value, commit.value)
        await model.exit()
    }

    /// A click just after a commit is a new scrub of something playing, so Back should resume it.
    @Test(.timeLimit(.minutes(1))) func aClickWhileAReportIsOutStartsACleanScrub() async throws {
        let (harness, model) = try await harness()
        harness.engine.settle()
        let gate = await holdingReports(harness)

        let first = Task { await model.send(.click) }
        await letOtherTasksRun()
        harness.engine.settle()
        let move = Task { await model.send(.moveRight) }
        await letOtherTasksRun()
        let commit = Task { await model.send(.click) }
        await letOtherTasksRun()
        let again = Task { await model.send(.click) }
        await letOtherTasksRun()

        #expect(model.controls.scrub?.wasPlaying == true)
        #expect(model.isPaused, "The new scrub pauses")

        await gate.open()
        _ = await (first.value, move.value, commit.value, again.value)
        await letOtherTasksRun()
        #expect(model.isPaused, "A queued play mustn't start video under the scrub")
        #expect(model.controls.scrub != nil)
        await model.exit()
    }

    @Test(.timeLimit(.minutes(1))) func aPlayPauseWhileAReportIsOutIsNotUndone() async throws {
        let (harness, model) = try await harness()
        harness.engine.settle()
        let gate = await holdingReports(harness)

        let click = Task { await model.send(.click) }
        await letOtherTasksRun()
        harness.engine.settle()
        let move = Task { await model.send(.moveRight) }
        await letOtherTasksRun()
        let commit = Task { await model.send(.click) }
        await letOtherTasksRun()
        let pause = Task { await model.send(.playPause) }
        await letOtherTasksRun()

        await gate.open()
        _ = await (click.value, move.value, commit.value, pause.value)
        await letOtherTasksRun()
        #expect(model.isPaused, "The person's pause should win")
        await model.exit()
    }

    @Test(.timeLimit(.minutes(1))) func aSecondDelayPressDuringAMoveIsKept() async throws {
        let (harness, model) = try await harness()
        let gate = await holdingReports(harness)

        let first = Task { await model.adjustAudioDelay(by: 1) }
        await letOtherTasksRun()
        let second = Task { await model.adjustAudioDelay(by: 1) }
        await letOtherTasksRun()

        #expect(model.options.audioDelay == 0.2)
        #expect(harness.engines.map(\.kind) == [.avPlayer, .mpv], "One move")
        #expect(harness.engine.applied.last?.audioDelay == 0.2)

        await gate.open()
        _ = await (first.value, second.value)
        await model.exit()
    }

    @Test(.timeLimit(.minutes(1))) func aPauseDuringAMoveIsKept() async throws {
        let (harness, model) = try await harness()
        let gate = await holdingReports(harness)

        let move = Task { await model.adjustAudioDelay(by: 1) }
        await letOtherTasksRun()
        let pause = Task { await model.send(.playPause) }
        await letOtherTasksRun()

        #expect(harness.engine.kind == .mpv)
        #expect(model.isPaused)

        await gate.open()
        _ = await (move.value, pause.value)
        await letOtherTasksRun()
        #expect(model.isPaused)
        await model.exit()
    }

    // MARK: Choosing what's already chosen

    @Test func choosingTheCurrentQualityDoesNotRestartPlayback() async throws {
        let (harness, model) = try await harness()
        let requests = await harness.client.playbackInfoRequests.count
        await model.setMaxBitrate(nil)
        #expect(harness.engines.count == 1)
        #expect(await harness.client.playbackInfoRequests.count == requests)
        await model.exit()
    }

    @Test func choosingTheCurrentTracksDoesNotRestartATranscode() async throws {
        let (harness, model) = try await harness()
        await harness.client.configure {
            $0.playbackInfoValue.mediaSources[0].bitRate = 5_000_000
            $0.playbackInfoValue.mediaSources[0].supportsTranscoding = true
            $0.playbackInfoValue.mediaSources[0].transcodingURL = URL(string: "http://server.invalid/master.m3u8")
        }
        await model.setMaxBitrate(1000)
        #expect(model.session?.route?.method == .transcode)
        let engines = harness.engines.count
        let requests = await harness.client.playbackInfoRequests.count
        await model.selectAudioTrack(id: 1)
        await model.selectSubtitleTrack(id: nil)
        #expect(harness.engines.count == engines)
        #expect(await harness.client.playbackInfoRequests.count == requests)
        await model.exit()
    }

    @Test func choosingTheCurrentVersionDoesNotRestartPlayback() async throws {
        let (harness, model) = try await harness()
        let current = try #require(model.session?.route?.mediaSourceID)
        await model.selectVersion(id: current)
        #expect(harness.engines.count == 1)
        await model.exit()
    }

    // MARK: A saved limit

    @Test func aSavedLimitThatCantPlayOffersAWayOut() async throws {
        let store = PlayerPreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let session = try await InMemoryJellyfinClient().signIn(username: "Test User", password: "password")
        var saved = PlayerPreferences()
        saved.maxBitrate = 1000
        store.save(saved, userID: session.user.id)
        let harness = Harness(item: episode("two"), store: store)
        try await harness.prepare()
        // A file over the limit, on a server that can't convert it.
        await harness.client.configure {
            $0.playbackInfoValue.mediaSources[0].bitRate = 5_000_000
            $0.playbackInfoValue.mediaSources[0].supportsTranscoding = false
        }

        await harness.model.start()

        guard case .failed = harness.model.phase else {
            Issue.record("Expected a failure, got \(harness.model.phase)")
            return
        }
        #expect(harness.model.canRemoveQualityLimit)

        await harness.model.removeQualityLimit()

        #expect(harness.model.phase == .playing)
        #expect(harness.model.session?.route?.method == .directPlay)
        #expect(store.load(userID: session.user.id).maxBitrate == nil)
        #expect(!harness.model.canRemoveQualityLimit)
        await harness.model.exit()
    }

    @Test func aFailureWithNoLimitOffersNothingExtra() async throws {
        let harness = Harness(item: episode("two"))
        try await harness.prepare()
        await harness.client.configure { $0.playbackInfoValue.mediaSources = [] }
        await harness.model.start()
        #expect(!harness.model.canRemoveQualityLimit)
        await harness.model.exit()
    }

    @Test func infoDescribesTheCurrentEngineAndRoute() async throws {
        let (kept, model) = try await harness()
        defer { withExtendedLifetime(kept) {} }
        #expect(model.infoRows.contains { $0.title == "Player" && $0.value == "AVPlayer" })
        await model.exit()
    }

    @Test func oneVersionOffersNoChoice() async throws {
        let (kept, model) = try await harness()
        defer { withExtendedLifetime(kept) {} }
        #expect(model.versions.isEmpty)
        await model.exit()
    }
}
