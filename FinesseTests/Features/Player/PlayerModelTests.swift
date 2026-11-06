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

    init(item: MediaItem, resume: Ticks? = nil) {
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
        await harness.model.backPressed()
        #expect(!harness.model.controlsVisible)
        await harness.model.togglePlayPause()
        harness.engine.settle()
        await harness.model.togglePlayPause()
        harness.engine.settle()
        await harness.model.backPressed()
        #expect(!harness.model.controlsVisible)
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

        await harness.model.backPressed()
        #expect(!harness.model.controlsVisible)
        #expect(harness.model.phase == .playing)
        #expect(await harness.client.stopReports.isEmpty)

        await harness.model.backPressed()
        #expect(harness.model.phase == .finished)
        #expect(await harness.client.stopReports.count == 1)
        #expect(await harness.client.stopReports.first?.position == Ticks(seconds: 42))

        await harness.model.exit()
        #expect(await harness.client.stopReports.count == 1)
    }

    @Test func backCancelsAScrubWithoutSeeking() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()
        harness.model.scrub(bySeconds: 30)
        await harness.model.backPressed()
        #expect(harness.model.scrubPosition == nil)
        #expect(harness.model.controlsVisible)
        #expect(harness.engine.seeks.isEmpty)
        await harness.model.exit()
    }

    @Test func clicksAddUpAndCommitOneSeekClampedToTheItem() async throws {
        let harness = Harness(item: episode(), resume: Ticks(seconds: 100))
        try await harness.prepare()
        await harness.model.start()
        harness.model.scrub(bySeconds: 10)
        harness.model.scrub(bySeconds: 10)
        #expect(harness.model.displayPosition == Ticks(seconds: 120))
        #expect(harness.engine.seeks.isEmpty)

        await harness.model.commitScrub()
        #expect(harness.engine.seeks == [Ticks(seconds: 120)])
        #expect(harness.model.scrubPosition == nil)
        #expect(await harness.client.progressReports.last?.position == Ticks(seconds: 120))

        harness.model.scrub(bySeconds: -500)
        #expect(harness.model.displayPosition == .zero)
        harness.model.scrub(bySeconds: 5000)
        #expect(harness.model.displayPosition == Ticks(seconds: 1000))
        await harness.model.exit()
    }

    @Test func panFractionScalesToTenMinutesAtMost() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()
        harness.model.scrub(byPanFraction: 0.5)
        #expect(harness.model.displayPosition == Ticks(seconds: 300))
        await harness.model.exit()
    }

    @Test func selectShowsHiddenControlsThenTogglesPause() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()
        await harness.model.backPressed()

        await harness.model.selectPressed()
        #expect(harness.model.controlsVisible)
        #expect(!harness.model.isPaused)

        await harness.model.selectPressed()
        #expect(harness.model.isPaused)
        #expect(await harness.client.progressReports.last?.isPaused == true)

        await harness.model.selectPressed()
        #expect(!harness.model.isPaused)
        await harness.model.exit()
    }

    @Test func controlsHideAfterTimeoutUnlessPausedOrInUse() async throws {
        let harness = Harness(item: episode())
        try await harness.prepare()
        await harness.model.start()

        harness.date += PlayerModel.controlsTimeout - 1
        await harness.model.tick()
        #expect(harness.model.controlsVisible)

        harness.model.focusMoved(toControls: true)
        harness.date += 10
        await harness.model.tick()
        #expect(harness.model.controlsVisible)

        // Returning to the bar restarts the timeout instead of hiding at once.
        harness.model.focusMoved(toControls: false)
        await harness.model.tick()
        #expect(harness.model.controlsVisible)

        harness.date += PlayerModel.controlsTimeout
        harness.engine.pause()
        harness.engine.settle()
        await harness.model.tick()
        #expect(harness.model.controlsVisible)

        harness.engine.play()
        harness.engine.settle()
        await harness.model.tick()
        #expect(!harness.model.controlsVisible)
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
