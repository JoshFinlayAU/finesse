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
    @ObservationIgnored private var info = PlaybackInfo()
    @ObservationIgnored private var reporter: PlaybackProgressReporter?
    /// Narrowed for good once an engine turns out not to reach a track this file has,
    /// so a later track change can't route back to it and lose the user's choice.
    @ObservationIgnored private var engines: [EngineCapabilities]

    init(
        client: any JellyfinClient,
        itemID: String,
        startPosition: Ticks = .zero,
        reportInterval: Duration = .seconds(10),
        engines: [EngineCapabilities] = EngineCapabilities.routingOrder,
        makeEngine: @escaping EngineFactory = PlaybackSession.makeDefaultEngine
    ) {
        self.client = client
        self.itemID = itemID
        self.startPosition = startPosition
        self.reportInterval = reportInterval
        self.engines = engines
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
        var route = try makeRoute(audioStreamIndex: nil, subtitle: .sourceDefault)
        var engine = start(route, at: startPosition)
        // The server's default audio can be a track this engine can't reach.
        if let moved = await routeAvoidingUnreachableAudio(route, on: engine, subtitle: .sourceDefault) {
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

    func play() async {
        engine?.play()
        await reporter?.reportProgress()
    }

    func pause() async {
        engine?.pause()
        await reporter?.reportProgress()
    }

    func seek(to position: Ticks) async {
        engine?.seek(to: position)
        await reporter?.reportProgress()
    }

    func selectAudioTrack(id: Int) async throws {
        try await changeTracks(audioStreamIndex: id, subtitle: currentSubtitleChoice)
    }

    func selectSubtitleTrack(id: Int?) async throws {
        try await changeTracks(
            audioStreamIndex: engine?.selectedAudioTrackID,
            subtitle: id.map(SubtitleChoice.stream) ?? .off
        )
    }

    /// Moves to another engine at the same position after this one fails. A failed engine is never
    /// tried again in this session, so this can't bounce between engines, and it ends with false
    /// once nothing is left. A transcode isn't tried, because the server only does those in software.
    func recoverFromEngineFailure() async -> Bool {
        guard let engine, let current = route else {
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
        engine.stop()
        start(next, at: position)
        reporter?.updateRoute(next)
        await reporter?.reportProgress()
        return true
    }

    /// Reports the final position while the engine still knows it, then ends the engine.
    func stop() async {
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
            isPaused: engine.state == .paused,
            audioStreamIndex: engine.selectedAudioTrackID,
            subtitleStreamIndex: engine.selectedSubtitleTrackID
        )
    }

    private func changeTracks(audioStreamIndex: Int?, subtitle: SubtitleChoice) async throws {
        guard let engine, let current = route else {
            return
        }
        // A transcode's tracks are burned into its URL, so the server has to make a new one.
        if current.method != .directPlay {
            let subtitleIndex: Int? = if case .stream(let index) = subtitle { index } else { nil }
            info = try await fetchInfo(
                startPosition: engine.position,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleIndex
            )
        }
        var next = try makeRoute(audioStreamIndex: audioStreamIndex, subtitle: subtitle)
        if next.engine == current.engine,
           let moved = await routeAvoidingUnreachableAudio(next, on: engine, subtitle: subtitle) {
            next = moved
        }
        if next.engine == current.engine, next.url == current.url {
            route = next
            reporter?.updateRoute(next)
            if let audioStreamIndex {
                engine.selectAudioTrack(id: audioStreamIndex)
            }
            engine.selectSubtitleTrack(id: next.subtitleStreamIndex)
        } else {
            let position = engine.position
            engine.stop()
            var moved = start(next, at: position)
            // The route can bring us back to an engine that can't reach the chosen audio.
            if let elsewhere = await routeAvoidingUnreachableAudio(next, on: moved, subtitle: subtitle) {
                moved.stop()
                next = elsewhere
                moved = start(elsewhere, at: position)
            }
            reporter?.updateRoute(next)
        }
        await reporter?.reportProgress()
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
            deviceProfile: DeviceProfileBuilder.make()
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
