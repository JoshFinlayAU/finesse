import Libmpv
import Observation
import os
import QuartzCore
import UIKit

/// Plays through libmpv, drawing into a CAMetalLayer via MoltenVK.
/// No mpv type leaves this file.
@MainActor
@Observable
final class MPVEngine: PlaybackEngine {
    let kind = PlaybackEngineKind.mpv
    private(set) var state = PlaybackState.idle
    private(set) var position = Ticks.zero
    private(set) var duration: Ticks?
    private(set) var audioTracks: [PlaybackTrack] = []
    private(set) var subtitleTracks: [PlaybackTrack] = []
    private(set) var selectedAudioTrackID: Int?
    private(set) var selectedSubtitleTrackID: Int?

    @ObservationIgnored private let renderView = MPVRenderView()
    @ObservationIgnored private let core: MPVCore?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var request: PlaybackLoadRequest?
    /// Jellyfin stream index to mpv track id. mpv numbers each track type separately.
    @ObservationIgnored private var trackIDs: [Int: Int64] = [:]
    /// The same, for reading a selection back: mpv track type and id to Jellyfin stream index.
    @ObservationIgnored private var streamIndexes: [String: Int] = [:]
    @ObservationIgnored private var isPaused = false
    @ObservationIgnored private var isWaitingForCache = false
    @ObservationIgnored private var isReady = false
    /// mpv refuses a seek before the file is open, so one made that early waits until it is.
    @ObservationIgnored private var pendingSeek: Ticks?

    #if DEBUG
    static var liveCoreCount: Int {
        MPVCore.liveCount.withLock { $0 }
    }
    #endif

    init() {
        core = MPVCore(layer: renderView.metalLayer)
        if core == nil {
            state = .failed("Could not start the player")
        }
    }

    /// Without this, mpv's own thread keeps it alive and playing after the last reference has gone.
    deinit {
        core?.shutdown()
    }

    func load(_ request: PlaybackLoadRequest) {
        guard let core else {
            return
        }
        state = .loading
        position = request.startPosition
        self.request = request
        audioTracks = request.audioTracks
        subtitleTracks = request.subtitleTracks
        selectedAudioTrackID = request.audioStreamIndex
        selectedSubtitleTrackID = request.subtitleStreamIndex
        isReady = false

        eventTask = Task { [weak self, events = core.events] in
            for await event in events {
                self?.handle(event)
            }
        }
        core.setString("start", String(request.startPosition.seconds))
        // Off until the file is loaded, so mpv's own default choice never flashes up.
        core.setString("sid", "no")
        core.command(["loadfile", request.url.absoluteString])
    }

    func play() {
        core?.setString("pause", "no")
    }

    func pause() {
        core?.setString("pause", "yes")
    }

    func seek(to position: Ticks) {
        self.position = position
        guard isReady else {
            pendingSeek = position
            return
        }
        core?.command(["seek", String(position.seconds), "absolute+exact"])
    }

    func selectAudioTrack(id: Int) {
        selectedAudioTrackID = id
        applyAudioSelection()
    }

    func selectSubtitleTrack(id: Int?) {
        selectedSubtitleTrackID = id
        applySubtitleSelection()
    }

    func apply(_ options: PlaybackOptions) {
        guard let core else {
            return
        }
        core.setString("speed", String(options.rate))
        core.setString("panscan", options.pictureMode == .fill ? "1" : "0")
        core.setString("keepaspect", options.pictureMode == .stretch ? "no" : "yes")
        core.setString("sub-scale", String(options.subtitleScale))
        core.setString("sub-pos", String(100 - options.subtitleRaise))
        core.setString("sub-delay", String(options.subtitleDelay))
        core.setString("audio-delay", String(options.audioDelay))
        if let text = options.subtitleTextColor {
            core.setString("sub-color", Self.mpvColor(text))
        }
        if let background = options.subtitleBackgroundColor {
            core.setString("sub-border-style", "background-box")
            core.setString("sub-back-color", Self.mpvColor(background))
        }
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
        core?.shutdown()
        state = .idle
    }

    func makeRenderView() -> UIView {
        renderView
    }

    /// Read back from mpv rather than assumed from the options it was given.
    var isSilent: Bool {
        core?.string("mute") == "yes" && core?.string("volume").flatMap(Double.init) == 0
    }

    /// mpv takes colours as red/green/blue/alpha from 0 to 1.
    private static func mpvColor(_ color: SubtitleColor) -> String {
        "\(color.red)/\(color.green)/\(color.blue)/\(color.alpha)"
    }

    #if DEBUG
    /// What mpv really has, as opposed to what was asked for. For tests.
    func property(_ name: String) -> String? {
        core?.string(name)
    }
    #endif

    /// What mpv has really selected, as opposed to what was asked for.
    var activeAudioTrackID: Int? {
        core?.int64("aid").flatMap { streamIndexes["audio-\($0)"] }
    }

    var activeSubtitleTrackID: Int? {
        core?.int64("sid").flatMap { streamIndexes["sub-\($0)"] }
    }

    private func handle(_ event: MPVCore.Event) {
        switch event {
        case .fileLoaded:
            mapTracks()
            applyAudioSelection()
            applySubtitleSelection()
        case .playbackRestart:
            isReady = true
            if let pendingSeek {
                self.pendingSeek = nil
                seek(to: pendingSeek)
            }
            updateState()
        case .position(let seconds):
            guard let seconds else {
                return
            }
            let ticks = Ticks(seconds: seconds)
            // mpv reports every frame, which is far more often than anything here needs.
            if abs(ticks.seconds - position.seconds) >= 0.25 {
                position = ticks
            }
        case .duration(let seconds):
            duration = seconds.map(Ticks.init(seconds:))
        case .paused(let paused):
            isPaused = paused
            updateState()
        case .waitingForCache(let waiting):
            isWaitingForCache = waiting
            updateState()
        case .ended:
            state = .ended
        case .failed(let message):
            state = .failed(message)
        }
    }

    private func updateState() {
        guard isReady, state != .ended else {
            return
        }
        if isWaitingForCache {
            state = .buffering
        } else {
            state = isPaused ? .paused : .playing
        }
    }

    /// mpv exposes each track's position in the file as ff-index.
    private func mapTracks() {
        guard let core, let request else {
            return
        }
        trackIDs = [:]
        streamIndexes = [:]
        let tracks = core.tracks()
        for stream in request.streams {
            let fileIndex = request.fileStreamIndex(ofStream: stream.index)
            if let track = tracks.first(where: { $0.streamIndex == fileIndex && fileIndex != nil }) {
                trackIDs[stream.index] = track.id
                streamIndexes["\(track.type)-\(track.id)"] = stream.index
            }
        }
    }

    private func applyAudioSelection() {
        guard let core, let index = selectedAudioTrackID, let id = trackIDs[index] else {
            return
        }
        core.setString("aid", String(id))
    }

    private func applySubtitleSelection() {
        guard let core else {
            return
        }
        guard let index = selectedSubtitleTrackID else {
            core.setString("sid", "no")
            return
        }
        if let id = trackIDs[index] {
            core.setString("sid", String(id))
        } else if let url = request?.streams.first(where: { $0.index == index })?.deliveryURL {
            core.command(["sub-add", url.absoluteString, "select"])
            if let id = core.int64("sid") {
                trackIDs[index] = id
                streamIndexes["sub-\(id)"] = index
            }
        }
    }
}

/// Owns the mpv handle and the thread that drains its events. mpv's client API is thread safe,
/// so calls can come from the main actor while that thread waits.
private final class MPVCore: @unchecked Sendable {
    enum Event: Sendable {
        case fileLoaded
        case playbackRestart
        case position(Double?)
        case duration(Double?)
        case paused(Bool)
        case waitingForCache(Bool)
        case ended
        case failed(String)
    }

    struct Track {
        var id: Int64
        var type: String
        var streamIndex: Int?
    }

    #if DEBUG
    static let liveCount = OSAllocatedUnfairLock(initialState: 0)
    #endif

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let handle: OpaquePointer
    /// mpv draws into this until it shuts down, so it has to outlive the view.
    private let layer: CAMetalLayer

    @MainActor
    init?(layer: CAMetalLayer) {
        guard let handle = mpv_create() else {
            return nil
        }
        self.handle = handle
        self.layer = layer
        (events, continuation) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .unbounded)

        var windowID = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &windowID)
        for (name, value) in [
            ("vo", "gpu-next"),
            ("gpu-api", "vulkan"),
            ("gpu-context", "moltenvk"),
            ("hwdec", "videotoolbox"),
            ("ao", "avfoundation,audiounit"),
            ("demuxer-max-bytes", "100MiB"),
            ("demuxer-max-back-bytes", "50MiB"),
        ] {
            mpv_set_option_string(handle, name, value)
        }
        // The simulator plays through the build Mac's speakers. See `PlaybackAudio`.
        if PlaybackAudio.isSilenced {
            mpv_set_option_string(handle, "mute", "yes")
            mpv_set_option_string(handle, "volume", "0")
        }
        guard mpv_initialize(handle) >= 0 else {
            mpv_terminate_destroy(handle)
            return nil
        }
        mpv_observe_property(handle, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "paused-for-cache", MPV_FORMAT_FLAG)

        #if DEBUG
        Self.liveCount.withLock { $0 += 1 }
        #endif
        Thread.detachNewThread { [self] in
            drainEvents()
        }
    }

    /// The handle is freed soon after shutdown, so nothing may reach it from then on.
    private let hasShutDown = OSAllocatedUnfairLock(initialState: false)

    func setString(_ name: String, _ value: String) {
        guard !hasShutDown.withLock({ $0 }) else {
            return
        }
        mpv_set_property_string(handle, name, value)
    }

    func int64(_ name: String) -> Int64? {
        guard !hasShutDown.withLock({ $0 }) else {
            return nil
        }
        var value: Int64 = 0
        return mpv_get_property(handle, name, MPV_FORMAT_INT64, &value) >= 0 ? value : nil
    }

    func string(_ name: String) -> String? {
        guard !hasShutDown.withLock({ $0 }), let value = mpv_get_property_string(handle, name) else {
            return nil
        }
        defer { mpv_free(value) }
        return String(cString: value)
    }

    func command(_ arguments: [String]) {
        guard !hasShutDown.withLock({ $0 }) else {
            return
        }
        sendCommand(arguments)
    }

    private func sendCommand(_ arguments: [String]) {
        var pointers: [UnsafePointer<CChar>?] = arguments.map { UnsafePointer(strdup($0)) }
        pointers.append(nil)
        mpv_command(handle, &pointers)
        pointers.forEach { free(UnsafeMutablePointer(mutating: $0)) }
    }

    func tracks() -> [Track] {
        guard let count = int64("track-list/count"), count > 0 else {
            return []
        }
        return (0..<count).compactMap { position in
            guard let id = int64("track-list/\(position)/id") else {
                return nil
            }
            return Track(
                id: id,
                type: string("track-list/\(position)/type") ?? "",
                streamIndex: int64("track-list/\(position)/ff-index").map(Int.init)
            )
        }
    }

    /// The event thread destroys the handle once mpv confirms it has shut down.
    func shutdown() {
        let isFirst = hasShutDown.withLock { hasShutDown in
            defer { hasShutDown = true }
            return !hasShutDown
        }
        if isFirst {
            sendCommand(["quit"])
        }
    }

    private func drainEvents() {
        while true {
            guard let event = mpv_wait_event(handle, -1)?.pointee else {
                continue
            }
            switch event.event_id {
            case MPV_EVENT_SHUTDOWN:
                continuation.finish()
                mpv_terminate_destroy(handle)
                #if DEBUG
                Self.liveCount.withLock { $0 -= 1 }
                #endif
                return
            case MPV_EVENT_FILE_LOADED:
                continuation.yield(.fileLoaded)
            case MPV_EVENT_PLAYBACK_RESTART:
                continuation.yield(.playbackRestart)
            case MPV_EVENT_END_FILE:
                let end = event.data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                if end.reason == MPV_END_FILE_REASON_EOF {
                    continuation.yield(.ended)
                } else if end.reason == MPV_END_FILE_REASON_ERROR {
                    continuation.yield(.failed(String(cString: mpv_error_string(end.error))))
                }
            case MPV_EVENT_PROPERTY_CHANGE:
                let property = event.data.assumingMemoryBound(to: mpv_event_property.self).pointee
                if let translated = Self.translate(property) {
                    continuation.yield(translated)
                }
            default:
                break
            }
        }
    }

    private static func translate(_ property: mpv_event_property) -> Event? {
        let double = property.format == MPV_FORMAT_DOUBLE
            ? property.data?.assumingMemoryBound(to: Double.self).pointee
            : nil
        let flag = property.format == MPV_FORMAT_FLAG
            ? property.data?.assumingMemoryBound(to: Int32.self).pointee != 0
            : false
        switch String(cString: property.name) {
        case "time-pos": return .position(double)
        case "duration": return .duration(double)
        case "pause": return .paused(flag)
        case "paused-for-cache": return .waitingForCache(flag)
        default: return nil
        }
    }
}

private final class MPVRenderView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer {
        layer as! CAMetalLayer
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        backgroundColor = .black
        updateDrawableSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = traitCollection.displayScale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
}
