#if DEBUG
import Observation
import UIKit

/// Launch with `-FinesseFakeServer -FinesseSeededPlayback` to play with made-up media segments and
/// no server or video. It exists because the test server has no segments. The screen, model and
/// buttons are the real ones. The engine and the segments are not, and the picture says so.
enum SeededPlayback {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-FinesseSeededPlayback")
    }

    /// Add `-FinesseSeededAVPlayerFails` or `-FinesseSeededBothFail` to make engines fail soon after
    /// loading, so the move between engines can be seen without a file that really breaks one.
    static var failingEngines: Set<PlaybackEngineKind> {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-FinesseSeededBothFail") {
            return [.avPlayer, .mpv]
        }
        return arguments.contains("-FinesseSeededAVPlayerFails") ? [.avPlayer] : []
    }

    /// `-FinesseSeededNoSegments` keeps skip buttons out of a test about something else.
    static var hasSegments: Bool {
        !ProcessInfo.processInfo.arguments.contains("-FinesseSeededNoSegments")
    }

    /// `-FinesseSeededBrightFrame` and `-FinesseSeededDarkFrame` are the worst cases for the glass.
    static var frameColor: UIColor {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-FinesseSeededBrightFrame") { return .white }
        if arguments.contains("-FinesseSeededDarkFrame") { return .black }
        return .darkGray
    }

    /// Its own place, emptied on launch, so one test's saved choices can't reach the next.
    /// `-FinesseSeededKeepPreferences` is for the test that checks they survive a relaunch.
    @MainActor static let preferenceStore: PlayerPreferenceStore = {
        let name = "SeededPlayback"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        if !ProcessInfo.processInfo.arguments.contains("-FinesseSeededKeepPreferences") {
            defaults.removePersistentDomain(forName: name)
        }
        return PlayerPreferenceStore(defaults: defaults)
    }()

    /// `-FinesseSeededStuckOnLimit` has a saved quality limit, on a file over it that can't be converted.
    static var isStuckOnLimit: Bool {
        ProcessInfo.processInfo.arguments.contains("-FinesseSeededStuckOnLimit")
    }

    /// Seconds after the start position: Skip Intro, Skip Credits, then one left to pass by itself.
    static let introRange = 4.0..<14.0
    static let creditsRange = 24.0..<30.0
    static let unusedRange = 40.0..<46.0

    @MainActor static func prepare(client: any JellyfinClient, request: PlaybackRequest) async {
        guard let fake = client as? InMemoryJellyfinClient else {
            return
        }
        let itemID = request.item.id
        let start = request.resumePosition?.seconds ?? 0
        func segment(_ id: String, _ kind: MediaSegmentKind, _ range: Range<Double>) -> MediaSegment {
            MediaSegment(
                id: id,
                itemID: itemID,
                kind: kind,
                start: Ticks(seconds: start + range.lowerBound),
                end: Ticks(seconds: start + range.upperBound)
            )
        }
        let segments = hasSegments ? [
            segment("seeded-intro", .intro, introRange),
            segment("seeded-credits", .outro, creditsRange),
            segment("seeded-unused", .outro, unusedRange),
        ] : []
        var source = PlaybackMediaSource(id: itemID)
        source.container = "mp4"
        source.supportsDirectPlay = true
        source.directPlayURL = URL(string: "http://seeded.invalid/video")
        var video = MediaStreamInfo(index: 0, kind: .video)
        video.codec = "h264"
        var audio = MediaStreamInfo(index: 1, kind: .audio)
        audio.codec = "aac"
        audio.displayTitle = "English AAC Stereo"
        var otherAudio = MediaStreamInfo(index: 2, kind: .audio)
        otherAudio.codec = "aac"
        otherAudio.displayTitle = "French AAC Stereo"
        var subtitle = MediaStreamInfo(index: 3, kind: .subtitle)
        subtitle.codec = "mov_text"
        subtitle.displayTitle = "English"
        var image = MediaStreamInfo(index: 4, kind: .subtitle)
        image.codec = "pgssub"
        image.displayTitle = "French PGS"
        source.streams = [video, audio, otherAudio, subtitle, image]
        source.bitRate = 5_000_000
        source.supportsTranscoding = true
        source.transcodingURL = URL(string: "http://seeded.invalid/master.m3u8")
        if isStuckOnLimit, let userID = await client.currentSession()?.user.id {
            source.supportsTranscoding = false
            var saved = preferenceStore.load(userID: userID)
            saved.maxBitrate = 1_000_000
            preferenceStore.save(saved, userID: userID)
        }
        let info = PlaybackInfo(playSessionID: "seeded", mediaSources: [source])
        await fake.configure {
            $0.playbackInfoValue = info
            $0.segments[itemID] = segments
            if let seriesID = request.item.seriesID {
                $0.allItems = (1...5).map {
                    var episode = MediaItem(id: "seeded-episode-\($0)", name: "Episode \($0)", kind: .episode)
                    episode.seriesID = seriesID
                    return episode
                }
                $0.allItems.insert(request.item, at: 2)
            }
            $0.chapters[itemID] = (0..<8).map {
                ItemChapter(index: $0, name: "Chapter \($0 + 1)", start: Ticks(seconds: Double($0) * 600))
            }
        }
    }
}

/// Moves its position in real time without playing anything.
@MainActor
@Observable
final class SeededPlaybackEngine: PlaybackEngine {
    let kind: PlaybackEngineKind
    private(set) var state = PlaybackState.idle
    private(set) var position = Ticks.zero
    private(set) var duration: Ticks? = Ticks(seconds: 6000)
    private(set) var audioTracks: [PlaybackTrack] = []
    private(set) var subtitleTracks: [PlaybackTrack] = []
    private(set) var selectedAudioTrackID: Int?
    private(set) var selectedSubtitleTrackID: Int?
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var secondsPlayed = 0.0

    init(kind: PlaybackEngineKind) {
        self.kind = kind
    }

    func load(_ request: PlaybackLoadRequest) {
        position = request.startPosition
        audioTracks = request.audioTracks
        subtitleTracks = request.subtitleTracks
        selectedAudioTrackID = request.audioStreamIndex
        selectedSubtitleTrackID = request.subtitleStreamIndex
        state = .playing
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.advance(by: 0.25)
            }
        }
    }

    func play() { state = .playing }
    func pause() { state = .paused }
    func seek(to position: Ticks) { self.position = position }
    func selectAudioTrack(id: Int) { selectedAudioTrackID = id }
    func selectSubtitleTrack(id: Int?) { selectedSubtitleTrackID = id }
    func apply(_ options: PlaybackOptions) {}

    func stop() {
        clock?.cancel()
        clock = nil
        state = .idle
    }

    /// It plays nothing, so it has nothing to hear.
    var isSilent: Bool { true }

    func makeRenderView() -> UIView {
        let label = UILabel()
        label.text = "Seeded playback on \(kind.rawValue): no video, and these segments are not from a server"
        label.isAccessibilityElement = true
        label.accessibilityIdentifier = "seededEngine"
        label.textAlignment = .center
        label.textColor = SeededPlayback.frameColor == .white ? .black : .white
        label.backgroundColor = SeededPlayback.frameColor
        return label
    }

    private func advance(by seconds: Double) {
        guard state == .playing else {
            return
        }
        position = Ticks(seconds: position.seconds + seconds)
        secondsPlayed += seconds
        if secondsPlayed >= 3, SeededPlayback.failingEngines.contains(kind) {
            state = .failed("The seeded \(kind.rawValue) engine failed")
        }
    }
}
#endif
