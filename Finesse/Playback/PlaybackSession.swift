import AVFoundation
import Observation

enum PlaybackSessionError: Error, Hashable, Sendable {
    case refusedByServer(String)
    case noPlayableSource
}

/// One playback of one item: asks the server what is available, routes it, runs the engine,
/// reports progress, and moves to the other engine if a track choice needs it.
@MainActor
@Observable
final class PlaybackSession {
    typealias EngineFactory = @MainActor (PlaybackEngineKind) -> any PlaybackEngine

    private(set) var engine: (any PlaybackEngine)?
    private(set) var route: PlaybackRoute?

    @ObservationIgnored private let client: any JellyfinClient
    @ObservationIgnored private let itemID: String
    @ObservationIgnored private let startPosition: Ticks
    @ObservationIgnored private let makeEngine: EngineFactory
    @ObservationIgnored private let reportInterval: Duration
    @ObservationIgnored private let deviceProfile: DeviceProfile
    @ObservationIgnored private var info = PlaybackInfo()
    @ObservationIgnored private var reporter: PlaybackProgressReporter?
    /// Narrowed for good once an engine turns out not to reach a track this file has,
    /// so a later track change can't route back to it and lose the user's choice.
    @ObservationIgnored private var engines: [EngineCapabilities]
    /// Set for good by `stop`. Anything still in flight checks this when it resumes, or it would
    /// start an engine nothing is left to stop.
    @ObservationIgnored private var isStopped = false
    /// Track changes run one at a time, because each can replace the engine.
    @ObservationIgnored private var trackChange: Task<Void, any Error>?
    /// What was last asked for, until the engine's state catches up. Engines change state later.
    @ObservationIgnored private var requestedPause: Bool?
    /// Whether a move to another engine should stay paused. Kept apart from the engine's state,
    /// because by then the old engine has stopped or failed and can't say.
    @ObservationIgnored private var staysPaused = false

    init(
        client: any JellyfinClient,
        itemID: String,
        startPosition: Ticks = .zero,
        reportInterval: Duration = .seconds(10),
        engines: [EngineCapabilities] = EngineCapabilities.routingOrder,
        deviceProfile: DeviceProfile = DeviceProfileBuilder.make(),
        makeEngine: @escaping EngineFactory = PlaybackSession.makeDefaultEngine
    ) {
        self.client = client
        self.itemID = itemID
        self.startPosition = startPosition
        self.reportInterval = reportInterval
        self.engines = engines
        self.deviceProfile = deviceProfile
        self.makeEngine = makeEngine
    }

    static func makeDefaultEngine(_ kind: PlaybackEngineKind) -> any PlaybackEngine {
        // Without this, audio follows the silent switch rules and won't route as film playback.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        switch kind {
        case .avPlayer: return AVPlayerEngine()
        case .mpv: return MPVEngine()
        }
    }

    func start() async throws {
        info = try await fetchInfo(startPosition: startPosition, audioStreamIndex: nil, subtitleStreamIndex: nil)
        guard !isStopped else {
            return
        }
        var route = try makeRoute(audioStreamIndex: nil, subtitle: .sourceDefault)
        var engine = start(route, at: startPosition)
        // The server's default audio can be a track this engine can't reach.
        let moved = await routeAvoidingUnreachableAudio(route, on: engine, subtitle: .sourceDefault)
        guard !isStopped else {
            return
        }
        if let moved {
            noteWhetherPaused()
            engine.stop()
            route = moved
            engine = start(moved, at: startPosition)
        }

        let reporter = PlaybackProgressReporter(
            client: client,
            itemID: itemID,
            playSessionID: info.playSessionID,
            route: route,
            interval: reportInterval
        ) { [weak self] in
            self?.snapshot ?? .init(position: engine.position, isPaused: false)
        }
        self.reporter = reporter
        await reporter.start()
    }

    /// Follows what was asked for straight away, so a report or a second press isn't left behind.
    /// Reading this after the engine has caught up ends that, and `PlayerModel.tick` reads it often.
    var isPaused: Bool {
        let enginePaused = engine?.state == .paused
        if let requestedPause, requestedPause != enginePaused {
            return requestedPause
        }
        requestedPause = nil
        return enginePaused
    }

    func play() async {
        staysPaused = false
        requestedPause = false
        engine?.play()
        await reporter?.reportProgress()
    }

    func pause() async {
        staysPaused = true
        requestedPause = true
        engine?.pause()
        await reporter?.reportProgress()
    }

    func seek(to position: Ticks) async {
        engine?.seek(to: position)
        await reporter?.reportProgress()
    }

    func selectAudioTrack(id: Int) async throws {
        try await enqueueTrackChange { [weak self] in
            (id, self?.currentSubtitleChoice ?? .off)
        }
    }

    func selectSubtitleTrack(id: Int?) async throws {
        try await enqueueTrackChange { [weak self] in
            (self?.engine?.selectedAudioTrackID, id.map(SubtitleChoice.stream) ?? .off)
        }
    }

    /// `choice` runs when its turn comes, so it builds on the change before it.
    private func enqueueTrackChange(_ choice: @escaping @MainActor () -> (Int?, SubtitleChoice)) async throws {
        let previous = trackChange
        let change = Task<Void, any Error> { [weak self] in
            _ = await previous?.result
            let (audio, subtitle) = choice()
            try await self?.changeTracks(audioStreamIndex: audio, subtitle: subtitle)
        }
        trackChange = change
        try await change.value
    }

    /// Moves to another engine at the same position after this one fails. A failed engine is never
    /// tried again in this session, so this can't bounce between engines, and it ends with false
    /// once nothing is left. A transcode isn't tried, because the server only does those in software.
    func recoverFromEngineFailure() async -> Bool {
        guard !isStopped, let engine, let current = route else {
            return false
        }
        let remaining = engines.filter { $0.engine != current.engine }
        guard !remaining.isEmpty, case .success(let next) = PlaybackRouter.route(
            sources: info.mediaSources,
            audioStreamIndex: engine.selectedAudioTrackID,
            subtitle: currentSubtitleChoice,
            engines: remaining
        ), next.method == .directPlay else {
            return false
        }
        engines = remaining
        let position = engine.position
        noteWhetherPaused()
        engine.stop()
        start(next, at: position)
        reporter?.updateRoute(next, playSessionID: info.playSessionID)
        await reporter?.reportProgress()
        return true
    }

    /// Reports the final position while the engine still knows it, then ends the engine.
    func stop() async {
        isStopped = true
        await reporter?.stop()
        reporter = nil
        engine?.stop()
        engine = nil
    }

    private var currentSubtitleChoice: SubtitleChoice {
        engine?.selectedSubtitleTrackID.map(SubtitleChoice.stream) ?? .off
    }

    private var snapshot: PlaybackProgressReporter.Snapshot? {
        guard let engine else {
            return nil
        }
        return .init(
            position: engine.position,
            isPaused: isPaused,
            audioStreamIndex: engine.selectedAudioTrackID,
            subtitleStreamIndex: engine.selectedSubtitleTrackID
        )
    }

    /// Catches a pause the engine did itself. Call this before stopping an engine to replace it.
    private func noteWhetherPaused() {
        if isPaused {
            staysPaused = true
        }
    }

    /// False once stop has arrived or the engine has been replaced, so an await's result is stale.
    private func isStillCurrent(_ engine: any PlaybackEngine) -> Bool {
        !isStopped && self.engine === engine
    }

    private func changeTracks(audioStreamIndex: Int?, subtitle: SubtitleChoice) async throws {
        guard !isStopped, let engine, let current = route else {
            return
        }
        let previousPlaySession = info.playSessionID
        // A transcode's tracks are burned into its URL, so the server has to make a new one.
        if current.method != .directPlay {
            let subtitleIndex: Int? = if case .stream(let index) = subtitle { index } else { nil }
            info = try await fetchInfo(
                startPosition: engine.position,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleIndex
            )
            guard isStillCurrent(engine) else {
                return
            }
        }
        var next = try makeRoute(audioStreamIndex: audioStreamIndex, subtitle: subtitle)
        if next.engine == current.engine {
            let moved = await routeAvoidingUnreachableAudio(next, on: engine, subtitle: subtitle)
            guard isStillCurrent(engine) else {
                return
            }
            next = moved ?? next
        }
        if next.engine == current.engine, next.url == current.url {
            route = next
            reporter?.updateRoute(next, playSessionID: info.playSessionID)
            if let audioStreamIndex {
                engine.selectAudioTrack(id: audioStreamIndex)
            }
            engine.selectSubtitleTrack(id: next.subtitleStreamIndex)
        } else {
            let position = engine.position
            noteWhetherPaused()
            engine.stop()
            var moved = start(next, at: position)
            // The route can bring us back to an engine that can't reach the chosen audio.
            let elsewhere = await routeAvoidingUnreachableAudio(next, on: moved, subtitle: subtitle)
            guard isStillCurrent(moved) else {
                return
            }
            if let elsewhere {
                noteWhetherPaused()
                moved.stop()
                next = elsewhere
                moved = start(elsewhere, at: position)
            }
            reporter?.updateRoute(next, playSessionID: info.playSessionID)
        }
        await reporter?.reportProgress()
        // Otherwise the old ffmpeg job runs on until the server's idle cleanup, about a minute later.
        if current.method != .directPlay, let previousPlaySession, previousPlaySession != info.playSessionID {
            try? await client.stopTranscoding(playSessionID: previousPlaySession)
        }
    }

    /// A route on another engine when this one can't reach the route's audio, otherwise nil.
    /// A transcode's tracks are already in its URL, so this only applies to direct play.
    private func routeAvoidingUnreachableAudio(
        _ route: PlaybackRoute,
        on engine: any PlaybackEngine,
        subtitle: SubtitleChoice
    ) async -> PlaybackRoute? {
        guard route.method == .directPlay, let audio = route.audioStreamIndex,
              !(await engine.canSelectAudioTrack(id: audio)) else {
            return nil
        }
        let remaining = engines.filter { $0.engine != route.engine }
        guard case .success(let moved) = PlaybackRouter.route(
            sources: info.mediaSources,
            audioStreamIndex: audio,
            subtitle: subtitle,
            engines: remaining
        ), moved.method == .directPlay else {
            return nil
        }
        engines = remaining
        return moved
    }

    @discardableResult
    private func start(_ route: PlaybackRoute, at position: Ticks) -> any PlaybackEngine {
        let engine = makeEngine(route.engine)
        requestedPause = staysPaused ? true : nil
        self.engine = engine
        self.route = route
        let streams = info.mediaSources.first { $0.id == route.mediaSourceID }?.streams ?? []
        engine.load(PlaybackLoadRequest(
            url: route.url,
            startPosition: position,
            streams: streams,
            audioStreamIndex: route.audioStreamIndex,
            subtitleStreamIndex: route.subtitleStreamIndex
        ))
        if staysPaused {
            engine.pause()
        }
        return engine
    }

    private func fetchInfo(
        startPosition: Ticks,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?
    ) async throws -> PlaybackInfo {
        let info = try await client.playbackInfo(PlaybackInfoRequest(
            itemID: itemID,
            startPosition: startPosition,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            deviceProfile: deviceProfile
        ))
        if let code = info.errorCode {
            throw PlaybackSessionError.refusedByServer(code)
        }
        return info
    }

    private func makeRoute(audioStreamIndex: Int?, subtitle: SubtitleChoice) throws -> PlaybackRoute {
        switch PlaybackRouter.route(
            sources: info.mediaSources,
            audioStreamIndex: audioStreamIndex,
            subtitle: subtitle,
            engines: engines
        ) {
        case .success(let route):
            return route
        case .failure:
            throw PlaybackSessionError.noPlayableSource
        }
    }
}
