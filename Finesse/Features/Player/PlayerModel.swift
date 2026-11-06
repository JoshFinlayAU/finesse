import Foundation
import Observation

/// The button a segment offers. Only intros and credits get one.
struct PlayerSkip: Equatable {
    var segmentID: String
    var title: String
    var end: Ticks
}

/// Everything the player screen shows and does. It reaches the engine only through
/// `PlaybackSession`, so both engines behave the same here.
@MainActor
@Observable
final class PlayerModel {
    enum Phase: Equatable {
        case loading
        case playing
        case upNext(MediaItem, secondsLeft: Int)
        case failed(String)
        case finished
    }

    static let upNextSeconds = 10
    static let clickScrubSeconds: TimeInterval = 10
    /// A full swipe across the touch surface covers this much, or the whole item if shorter.
    static let panScrubSeconds: TimeInterval = 600
    static let controlsTimeout: TimeInterval = 5

    private(set) var item: MediaItem
    private(set) var phase = Phase.loading
    private(set) var session: PlaybackSession?
    private(set) var skip: PlayerSkip?
    private(set) var scrubPosition: Ticks?
    private(set) var controlsVisible = true
    private(set) var trackError: String?
    /// True while focus is away from the transport bar, such as in a track menu.
    private(set) var keepControlsVisible = false

    @ObservationIgnored private let client: any JellyfinClient
    @ObservationIgnored private var resumePosition: Ticks?
    @ObservationIgnored private let makeEngine: PlaybackSession.EngineFactory
    @ObservationIgnored private let engines: [EngineCapabilities]
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var segments: [MediaSegment] = []
    @ObservationIgnored private var skippedSegmentIDs: Set<String> = []
    @ObservationIgnored private var lastActivity: Date
    @ObservationIgnored private var hasHandledEnd = false

    init(
        client: any JellyfinClient,
        request: PlaybackRequest,
        engines: [EngineCapabilities] = EngineCapabilities.routingOrder,
        now: @escaping @MainActor () -> Date = { .now },
        makeEngine: @escaping PlaybackSession.EngineFactory = PlaybackSession.makeDefaultEngine
    ) {
        self.client = client
        item = request.item
        resumePosition = request.resumePosition
        self.makeEngine = makeEngine
        self.engines = engines
        self.now = now
        lastActivity = now()
    }

    var engine: (any PlaybackEngine)? {
        session?.engine
    }

    /// Where the transport bar should show, which leads the engine during a scrub.
    var displayPosition: Ticks {
        scrubPosition ?? engine?.position ?? .zero
    }

    var duration: Ticks? {
        engine?.duration ?? item.runTime
    }

    var isPaused: Bool {
        engine?.state == .paused
    }

    var isBuffering: Bool {
        guard let state = engine?.state else {
            return false
        }
        return state == .loading || state == .buffering
    }

    func start() async {
        phase = .loading
        hasHandledEnd = false
        skip = nil
        skippedSegmentIDs = []
        segments = []
        noteActivity()
        let session = PlaybackSession(
            client: client,
            itemID: item.id,
            startPosition: resumePosition ?? .zero,
            engines: engines,
            makeEngine: makeEngine
        )
        self.session = session
        do {
            try await session.start()
            phase = .playing
        } catch {
            self.session = nil
            phase = .failed(error.userMessage)
            return
        }
        // Most servers have no segments, and playback doesn't depend on them.
        segments = (try? await client.mediaSegments(itemID: item.id)) ?? []
    }

    /// Call a few times a second while the screen is up.
    func tick() async {
        guard phase == .playing, let engine else {
            return
        }
        switch engine.state {
        case .ended:
            await handleEnd()
            return
        case .failed(let message):
            if await session?.recoverFromEngineFailure() == true {
                return
            }
            await session?.stop()
            session = nil
            phase = .failed(message)
            return
        default:
            break
        }
        updateSkip(position: engine.position)
        if controlsVisible, !isPaused, scrubPosition == nil, !keepControlsVisible,
           now().timeIntervalSince(lastActivity) >= Self.controlsTimeout {
            controlsVisible = false
        }
    }

    /// Call once a second while the up next card is showing.
    func upNextTick() async {
        guard case .upNext(let next, let secondsLeft) = phase else {
            return
        }
        if secondsLeft <= 1 {
            // The countdown's own task ends when the phase changes. If starting the next episode
            // ran inside it, that would cancel the episode's network requests.
            await Task { await play(next) }.value
        } else {
            phase = .upNext(next, secondsLeft: secondsLeft - 1)
        }
    }

    func playNext() async {
        if case .upNext(let next, _) = phase {
            await play(next)
        }
    }

    func cancelUpNext() {
        if case .upNext = phase {
            phase = .finished
        }
    }

    func togglePlayPause() async {
        noteActivity()
        if isPaused {
            await session?.play()
        } else {
            await session?.pause()
        }
    }

    /// Select on the transport bar: commits a scrub, shows hidden controls, otherwise toggles.
    func selectPressed() async {
        if scrubPosition != nil {
            await commitScrub()
        } else if !controlsVisible {
            noteActivity()
        } else {
            await togglePlayPause()
        }
    }

    func noteActivity() {
        lastActivity = now()
        controlsVisible = true
    }

    /// Coming back from the track buttons counts as activity, or the controls would vanish at once.
    func focusMoved(toControls: Bool) {
        if keepControlsVisible, !toControls {
            noteActivity()
        }
        keepControlsVisible = toControls
    }

    /// Back steps out one level at a time: a scrub, then the controls, then the player.
    func backPressed() async {
        if case .upNext = phase {
            cancelUpNext()
        } else if phase != .playing {
            await exit()
        } else if scrubPosition != nil {
            scrubPosition = nil
            noteActivity()
        } else if controlsVisible {
            controlsVisible = false
        } else {
            await exit()
        }
    }

    /// Reports the final position, so anything reloading afterwards sees it.
    func exit() async {
        await session?.stop()
        session = nil
        phase = .finished
    }

    func scrub(bySeconds seconds: TimeInterval) {
        guard let engine else {
            return
        }
        noteActivity()
        let current = scrubPosition ?? engine.position
        var target = max(current.seconds + seconds, 0)
        if let duration = duration?.seconds, duration > 0 {
            target = min(target, duration)
        }
        scrubPosition = Ticks(seconds: target)
    }

    /// `fraction` is the part of the touch surface swiped since the last call.
    func scrub(byPanFraction fraction: Double) {
        let span = min(duration?.seconds ?? Self.panScrubSeconds, Self.panScrubSeconds)
        scrub(bySeconds: fraction * span)
    }

    func commitScrub() async {
        guard let target = scrubPosition else {
            return
        }
        scrubPosition = nil
        noteActivity()
        await session?.seek(to: target)
    }

    func skipPressed() async {
        guard let skip else {
            return
        }
        skippedSegmentIDs.insert(skip.segmentID)
        self.skip = nil
        await session?.seek(to: skip.end)
    }

    func selectAudioTrack(id: Int) async {
        noteActivity()
        do {
            try await session?.selectAudioTrack(id: id)
        } catch {
            trackError = error.userMessage
        }
    }

    func selectSubtitleTrack(id: Int?) async {
        noteActivity()
        do {
            try await session?.selectSubtitleTrack(id: id)
        } catch {
            trackError = error.userMessage
        }
    }

    func clearTrackError() {
        trackError = nil
    }

    private func updateSkip(position: Ticks) {
        let segment = segments.first {
            ($0.kind == .intro || $0.kind == .outro)
                && $0.start <= position && position < $0.end
                && !skippedSegmentIDs.contains($0.id)
        }
        skip = segment.map {
            PlayerSkip(segmentID: $0.id, title: $0.kind == .intro ? "Skip Intro" : "Skip Credits", end: $0.end)
        }
    }

    /// Stop goes first, so the server has marked this episode played when asked what's next.
    private func handleEnd() async {
        guard !hasHandledEnd else {
            return
        }
        hasHandledEnd = true
        skip = nil
        await session?.stop()
        session = nil
        guard item.kind == .episode, let seriesID = item.seriesID,
              let next = try? await client.nextUp(seriesID: seriesID), next.id != item.id else {
            phase = .finished
            return
        }
        phase = .upNext(next, secondsLeft: Self.upNextSeconds)
    }

    private func play(_ next: MediaItem) async {
        item = next
        let saved = next.userState.playbackPosition
        resumePosition = saved > .zero ? saved : nil
        await start()
    }
}
