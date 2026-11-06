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
    /// Rows in the quality panel, in bits per second. Nil plays the file as it is.
    static let bitrateChoices: [Int?] = [nil, 40_000_000, 20_000_000, 10_000_000, 8_000_000, 4_000_000, 2_000_000]
    static let delayStep: TimeInterval = 0.1
    static let subtitleScaleStep = 0.1
    static let subtitleRaiseStep = 5

    private(set) var item: MediaItem
    private(set) var phase = Phase.loading
    private(set) var session: PlaybackSession?
    private(set) var skip: PlayerSkip?
    private(set) var controls = PlayerControls()
    private(set) var trackError: String?
    private(set) var chapters: [ItemChapter] = []
    /// Every episode of the series, in order. Empty for a movie.
    private(set) var episodes: [MediaItem] = []
    /// Survives moving to another episode, so the next one starts the same way.
    private(set) var options = PlaybackOptions()
    private(set) var preferences = PlayerPreferences()

    @ObservationIgnored private let client: any JellyfinClient
    @ObservationIgnored private var resumePosition: Ticks?
    @ObservationIgnored private let makeEngine: PlaybackSession.EngineFactory
    @ObservationIgnored private let engines: [EngineCapabilities]
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var segments: [MediaSegment] = []
    @ObservationIgnored private var skippedSegmentIDs: Set<String> = []
    @ObservationIgnored private var hasHandledEnd = false
    @ObservationIgnored private let preferenceStore: PlayerPreferenceStore
    @ObservationIgnored private let captionStyle: SystemCaptionStyle
    @ObservationIgnored private var preferencesUserID: String?
    /// Set by `exit`. Whatever was in flight checks this when it resumes, because the player is closing.
    @ObservationIgnored private var isExiting = false

    init(
        client: any JellyfinClient,
        request: PlaybackRequest,
        engines: [EngineCapabilities] = EngineCapabilities.routingOrder,
        now: @escaping @MainActor () -> Date = { .now },
        preferenceStore: PlayerPreferenceStore = PlayerPreferenceStore(),
        captionStyle: SystemCaptionStyle = .current(),
        makeEngine: @escaping PlaybackSession.EngineFactory = PlaybackSession.makeDefaultEngine
    ) {
        self.client = client
        item = request.item
        resumePosition = request.resumePosition
        self.makeEngine = makeEngine
        self.engines = engines
        self.now = now
        self.preferenceStore = preferenceStore
        self.captionStyle = captionStyle
    }

    var engine: (any PlaybackEngine)? {
        session?.engine
    }

    var scrubPosition: Ticks? {
        controls.scrub?.target
    }

    /// Where the bar should show, which leads the engine during a scrub.
    var displayPosition: Ticks {
        scrubPosition ?? engine?.position ?? .zero
    }

    var previousEpisode: MediaItem? {
        episodes.firstIndex { $0.id == item.id }.flatMap { $0 > 0 ? episodes[$0 - 1] : nil }
    }

    var nextEpisode: MediaItem? {
        episodes.firstIndex { $0.id == item.id }.flatMap { $0 + 1 < episodes.count ? episodes[$0 + 1] : nil }
    }

    /// The panels worth opening for this item, in the order the bar shows them.
    var panels: [PlayerPanel] {
        PlayerPanel.allCases.filter {
            switch $0 {
            case .chapters: !chapters.isEmpty
            case .episodes: !episodes.isEmpty
            default: true
            }
        }
    }

    /// The row a panel opens on, which is whatever is in use. Also the row's accessibility identifier.
    func initialRowID(of panel: PlayerPanel) -> String {
        switch panel {
        case .audio: "audio-\(engine?.selectedAudioTrackID ?? 0)"
        case .subtitles: engine?.selectedSubtitleTrackID.map { "subtitle-\($0)" } ?? "subtitle-off"
        case .playback: "rate-\(options.rate)"
        case .chapters: "chapter-\(chapter(at: displayPosition)?.index ?? 0)"
        case .episodes: "episode-\(item.id)"
        case .quality: "bitrate-\(preferences.maxBitrate ?? 0)"
        case .info: "infoRows"
        }
    }

    /// The chapter playing at `position`, for showing while scrubbing.
    func chapter(at position: Ticks) -> ItemChapter? {
        chapters.last { $0.start <= position }
    }

    func chapterImageURL(_ chapter: ItemChapter) -> URL? {
        client.imageURL(itemID: item.id, kind: .chapter, tag: chapter.imageTag, index: chapter.index, maxWidth: 480)
    }

    func thumbnailURL(_ episode: MediaItem) -> URL? {
        client.imageURL(itemID: episode.id, kind: .primary, tag: episode.images.primaryTag, index: nil, maxWidth: 480)
    }

    var infoRows: [PlayerInfo.Row] {
        PlayerInfo.rows(
            source: session?.currentSource,
            route: session?.route,
            audioIndex: engine?.selectedAudioTrackID,
            subtitleIndex: engine?.selectedSubtitleTrackID
        )
    }

    /// Versions of this item when the server has more than one.
    var versions: [PlaybackMediaSource] {
        let sources = session?.mediaSources ?? []
        return sources.count > 1 ? sources : []
    }

    func availability(of option: PlaybackOption) -> PlaybackOptionAvailability {
        session?.availability(of: option) ?? .unavailable("Playback hasn't started yet.")
    }

    /// A limit makes the server convert the video, which is the one thing here that costs it anything.
    var qualityNote: String? {
        preferences.maxBitrate == nil ? nil : "The server converts anything above this, which uses its processor."
    }

    var duration: Ticks? {
        engine?.duration ?? item.runTime
    }

    var isPaused: Bool {
        session?.isPaused ?? false
    }

    var isBuffering: Bool {
        guard let state = engine?.state else {
            return false
        }
        return state == .loading || state == .buffering
    }

    func start() async {
        guard !isExiting else {
            return
        }
        phase = .loading
        hasHandledEnd = false
        skip = nil
        skippedSegmentIDs = []
        segments = []
        chapters = []
        controls.reset()
        await loadPreferences()
        guard !isExiting else {
            return
        }
        let session = PlaybackSession(
            client: client,
            itemID: item.id,
            startPosition: resumePosition ?? .zero,
            options: options,
            maxBitrate: preferences.maxBitrate,
            captionStyle: captionStyle,
            engines: engines,
            makeEngine: makeEngine
        )
        self.session = session
        do {
            try await session.start()
            guard !isExiting, self.session === session else {
                return
            }
            phase = .playing
        } catch {
            guard !isExiting, self.session === session else {
                return
            }
            self.session = nil
            phase = .failed(error.userMessage)
            return
        }
        // Most servers have no segments, and playback doesn't depend on any of these.
        async let segments = try? client.mediaSegments(itemID: item.id)
        async let chapters = try? client.chapters(itemID: item.id)
        async let episodes = loadEpisodes()
        let (loadedSegments, loadedChapters, loadedEpisodes) = await (segments, chapters, episodes)
        if self.session === session {
            self.segments = loadedSegments ?? []
            self.chapters = loadedChapters ?? []
            self.episodes = loadedEpisodes
        }
    }

    private func loadEpisodes() async -> [MediaItem] {
        guard item.kind == .episode, let seriesID = item.seriesID else {
            return []
        }
        if episodes.first?.seriesID == seriesID {
            return episodes
        }
        return (try? await client.episodes(seriesID: seriesID, seasonID: nil)) ?? []
    }

    private func loadPreferences() async {
        guard preferencesUserID == nil, let userID = await client.currentSession()?.user.id else {
            return
        }
        preferencesUserID = userID
        preferences = preferenceStore.load(userID: userID)
        options.subtitleScale = preferences.subtitleScale ?? captionStyle.scale.map(Self.clampedScale) ?? 1
        options.subtitleTextColor = captionStyle.textColor
        options.subtitleBackgroundColor = captionStyle.backgroundColor
        options.subtitleRaise = preferences.subtitleRaise
        options.pictureMode = preferences.pictureMode
    }

    /// Call a few times a second while the screen is up.
    func tick() async {
        guard phase == .playing, !isExiting, let engine else {
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
            guard !isExiting else {
                return
            }
            // Try Again carries on from here. The stop below has told the server this position.
            if engine.position > .zero {
                resumePosition = engine.position
            }
            await session?.stop()
            guard !isExiting else {
                return
            }
            session = nil
            phase = .failed(message)
            return
        default:
            break
        }
        updateSkip(position: engine.position)
        await send(.tick)
    }

    /// Everything the remote does while playing goes through here.
    func send(_ event: PlayerControls.Event) async {
        guard phase == .playing else {
            return
        }
        let context = PlayerControls.Context(
            position: engine?.position ?? .zero,
            duration: duration,
            isPaused: isPaused,
            now: now()
        )
        let effects = controls.handle(event, context)
        session?.setLiftsSubtitles(controls.isShowing)
        for effect in effects {
            switch effect {
            case .pause: await session?.pause()
            case .play: await session?.play()
            case .toggle: await togglePlayPause()
            case .seek(let position): await session?.seek(to: position)
            case .exit: await exit()
            }
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
        if isPaused {
            await session?.play()
        } else {
            await session?.pause()
        }
    }

    /// Back steps out one level at a time, and with nothing showing it leaves the player.
    func backPressed() async {
        if case .upNext = phase {
            cancelUpNext()
        } else if phase == .playing {
            await send(.back)
        } else {
            await exit()
        }
    }

    /// Reports the final position, so anything reloading afterwards sees it.
    func exit() async {
        isExiting = true
        await session?.stop()
        session = nil
        phase = .finished
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
        do {
            try await session?.selectAudioTrack(id: id)
        } catch {
            trackError = error.userMessage
        }
    }

    func selectSubtitleTrack(id: Int?) async {
        do {
            try await session?.selectSubtitleTrack(id: id)
        } catch {
            trackError = error.userMessage
        }
    }

    func setRate(_ rate: Double) async {
        await update { $0.rate = rate }
    }

    func setPictureMode(_ mode: PictureMode) async {
        preferences.pictureMode = mode
        savePreferences()
        await update { $0.pictureMode = mode }
    }

    func adjustSubtitleScale(by steps: Int) async {
        let clamped = Self.clampedScale(options.subtitleScale + Double(steps) * Self.subtitleScaleStep)
        preferences.subtitleScale = clamped
        savePreferences()
        await update { $0.subtitleScale = clamped }
    }

    func adjustSubtitleRaise(by steps: Int) async {
        let limits = PlaybackOptions.subtitleRaises
        let clamped = min(max(options.subtitleRaise + steps * Self.subtitleRaiseStep, limits.lowerBound), limits.upperBound)
        preferences.subtitleRaise = clamped
        savePreferences()
        await update { $0.subtitleRaise = clamped }
    }

    func adjustSubtitleDelay(by steps: Int) async {
        let delay = stepped(options.subtitleDelay, by: steps)
        await update { $0.subtitleDelay = delay }
    }

    func adjustAudioDelay(by steps: Int) async {
        let delay = stepped(options.audioDelay, by: steps)
        await update { $0.audioDelay = delay }
    }

    func setMaxBitrate(_ bitrate: Int?) async {
        let source = session?.preferredSourceID
        do {
            try await session?.setQuality(maxBitrate: bitrate, sourceID: source)
            preferences.maxBitrate = bitrate
            savePreferences()
        } catch {
            trackError = error.userMessage
        }
    }

    func selectVersion(id: String) async {
        do {
            try await session?.setQuality(maxBitrate: session?.maxBitrate, sourceID: id)
        } catch {
            trackError = error.userMessage
        }
    }

    func selectChapter(_ chapter: ItemChapter) async {
        await session?.seek(to: chapter.start)
        controls.reset()
        session?.setLiftsSubtitles(false)
    }

    /// Stop goes first, so the server has this episode's position before the next one starts.
    func playEpisode(_ episode: MediaItem) async {
        guard phase == .playing else {
            return
        }
        controls.reset()
        await session?.stop()
        guard !isExiting else {
            return
        }
        session = nil
        await play(episode)
    }

    private static func clampedScale(_ scale: Double) -> Double {
        let limits = PlaybackOptions.subtitleScales
        return min(max((scale * 10).rounded() / 10, limits.lowerBound), limits.upperBound)
    }

    private func stepped(_ delay: TimeInterval, by steps: Int) -> TimeInterval {
        let limits = PlaybackOptions.delays
        let value = ((delay + Double(steps) * Self.delayStep) * 10).rounded() / 10
        return min(max(value, limits.lowerBound), limits.upperBound)
    }

    private func update(_ change: (inout PlaybackOptions) -> Void) async {
        var new = options
        change(&new)
        do {
            try await session?.setOptions(new)
            options = new
        } catch {
            trackError = error.userMessage
        }
    }

    private func savePreferences() {
        if let preferencesUserID {
            preferenceStore.save(preferences, userID: preferencesUserID)
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
        guard !isExiting else {
            return
        }
        session = nil
        guard item.kind == .episode, let seriesID = item.seriesID,
              let next = try? await client.nextUp(seriesID: seriesID), next.id != item.id else {
            if !isExiting {
                phase = .finished
            }
            return
        }
        guard !isExiting else {
            return
        }
        phase = .upNext(next, secondsLeft: Self.upNextSeconds)
    }

    private func play(_ next: MediaItem) async {
        guard !isExiting else {
            return
        }
        item = next
        let saved = next.userState.playbackPosition
        resumePosition = saved > .zero ? saved : nil
        // A timing offset fixes one file, so it doesn't carry over.
        options.subtitleDelay = 0
        options.audioDelay = 0
        await start()
    }
}
