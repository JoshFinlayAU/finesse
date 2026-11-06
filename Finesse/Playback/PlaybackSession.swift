import Foundation
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

    init(
        client: any JellyfinClient,
        itemID: String,
        startPosition: Ticks = .zero,
        reportInterval: Duration = .seconds(10),
        makeEngine: @escaping EngineFactory = PlaybackSession.makeDefaultEngine
    ) {
        self.client = client
        self.itemID = itemID
        self.startPosition = startPosition
        self.reportInterval = reportInterval
        self.makeEngine = makeEngine
    }

    static func makeDefaultEngine(_ kind: PlaybackEngineKind) -> any PlaybackEngine {
        switch kind {
        case .avPlayer: AVPlayerEngine()
        case .mpv: MPVEngine()
        }
    }

    func start() async throws {
        info = try await fetchInfo(audioStreamIndex: nil, subtitleStreamIndex: nil)
        let route = try makeRoute(audioStreamIndex: nil, subtitle: .sourceDefault)
        let engine = start(route, at: startPosition)

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
            info = try await fetchInfo(audioStreamIndex: audioStreamIndex, subtitleStreamIndex: subtitleIndex)
        }
        let next = try makeRoute(audioStreamIndex: audioStreamIndex, subtitle: subtitle)
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
            start(next, at: position)
            reporter?.updateRoute(next)
        }
        await reporter?.reportProgress()
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

    private func fetchInfo(audioStreamIndex: Int?, subtitleStreamIndex: Int?) async throws -> PlaybackInfo {
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
        switch PlaybackRouter.route(sources: info.mediaSources, audioStreamIndex: audioStreamIndex, subtitle: subtitle) {
        case .success(let route):
            return route
        case .failure:
            throw PlaybackSessionError.noPlayableSource
        }
    }
}
