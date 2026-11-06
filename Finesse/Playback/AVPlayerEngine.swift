import AVFoundation
import AVKit
import Combine
import Observation
import UIKit

@MainActor
@Observable
final class AVPlayerEngine: PlaybackEngine {
    let kind = PlaybackEngineKind.avPlayer
    private(set) var state = PlaybackState.idle
    private(set) var position = Ticks.zero
    private(set) var duration: Ticks?
    private(set) var audioTracks: [PlaybackTrack] = []
    private(set) var subtitleTracks: [PlaybackTrack] = []
    private(set) var selectedAudioTrackID: Int?
    private(set) var selectedSubtitleTrackID: Int?

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var pendingStart: Ticks?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private weak var renderView: AVPlayerRenderView?

    func load(_ request: PlaybackLoadRequest) {
        state = .loading
        position = request.startPosition
        audioTracks = request.audioTracks
        subtitleTracks = request.subtitleTracks
        selectedAudioTrackID = request.audioStreamIndex
        selectedSubtitleTrackID = request.subtitleStreamIndex
        pendingStart = request.startPosition > .zero ? request.startPosition : nil
        hasStarted = false

        let item = AVPlayerItem(url: request.url)
        observe(item)
        player.replaceCurrentItem(with: item)
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to position: Ticks) {
        self.position = position
        player.seek(to: Self.time(position), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// An MP4's audio tracks are only switchable when the file groups them, which many don't.
    func canSelectAudioTrack(id: Int) async -> Bool {
        guard let offset = audioTracks.filter({ !$0.isExternal }).firstIndex(where: { $0.id == id }) else {
            return false
        }
        // A file with one audio track may have no selection group at all, so the first is always reachable.
        return offset < max(await selectableTrackCount(.audible), 1)
    }

    func selectAudioTrack(id: Int) {
        selectedAudioTrackID = id
        applySelection(.audible, trackID: id, tracks: audioTracks)
    }

    func selectSubtitleTrack(id: Int?) {
        selectedSubtitleTrackID = id
        applySelection(.legible, trackID: id, tracks: subtitleTracks)
    }

    func stop() {
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        cancellables.removeAll()
        player.replaceCurrentItem(with: nil)
        renderView?.clearDisplayCriteria()
        state = .idle
    }

    func makeRenderView() -> UIView {
        let view = AVPlayerRenderView(player: player)
        renderView = view
        return view
    }

    /// How many tracks AVPlayer can actually switch between, which can be fewer than the file has.
    func selectableTrackCount(_ characteristic: AVMediaCharacteristic) async -> Int {
        guard let asset = player.currentItem?.asset,
              let group = try? await asset.loadMediaSelectionGroup(for: characteristic) else {
            return 0
        }
        return group.options.count
    }

    /// What AVPlayer has really selected, as opposed to what was asked for.
    func activeTrackID(_ characteristic: AVMediaCharacteristic) async -> Int? {
        guard let item = player.currentItem,
              let group = try? await item.asset.loadMediaSelectionGroup(for: characteristic),
              let option = item.currentMediaSelection.selectedMediaOption(in: group),
              let offset = group.options.firstIndex(of: option) else {
            return nil
        }
        let tracks = characteristic == .audible ? audioTracks : subtitleTracks
        let embedded = tracks.filter { !$0.isExternal }
        return offset < embedded.count ? embedded[offset].id : nil
    }

    private func observe(_ item: AVPlayerItem) {
        cancellables.removeAll()
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated { self?.itemStatusChanged(status, item: item) }
            }
            .store(in: &cancellables)
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated { self?.timeControlStatusChanged(status) }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.state = .ended }
            }
            .store(in: &cancellables)
        if timeObserver == nil {
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(value: 1, timescale: 2),
                queue: .main
            ) { [weak self] time in
                MainActor.assumeIsolated { self?.timeChanged(time) }
            }
        }
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status, item: AVPlayerItem) {
        switch status {
        case .readyToPlay:
            guard !hasStarted else {
                return
            }
            hasStarted = true
            duration = Self.ticks(item.duration)
            renderView?.applyDisplayCriteria(of: item.asset)
            applySelection(.audible, trackID: selectedAudioTrackID, tracks: audioTracks)
            applySelection(.legible, trackID: selectedSubtitleTrackID, tracks: subtitleTracks)
            if let pendingStart {
                self.pendingStart = nil
                player.seek(to: Self.time(pendingStart), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    Task { @MainActor in self?.player.play() }
                }
            } else {
                player.play()
            }
        case .failed:
            state = .failed(item.error?.localizedDescription ?? "Playback failed")
        default:
            break
        }
    }

    private func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
        guard hasStarted, state != .ended else {
            return
        }
        switch status {
        case .playing: state = .playing
        case .paused: state = .paused
        case .waitingToPlayAtSpecifiedRate: state = .buffering
        @unknown default: break
        }
    }

    private func timeChanged(_ time: CMTime) {
        guard pendingStart == nil, let ticks = Self.ticks(time) else {
            return
        }
        position = ticks
    }

    /// Server streams and AVPlayer's options are matched by order among embedded tracks.
    private func applySelection(_ characteristic: AVMediaCharacteristic, trackID: Int?, tracks: [PlaybackTrack]) {
        guard let item = player.currentItem else {
            return
        }
        Task { [weak item] in
            guard let item,
                  let group = try? await item.asset.loadMediaSelectionGroup(for: characteristic) else {
                return
            }
            let embedded = tracks.filter { !$0.isExternal }
            guard let trackID else {
                item.select(nil, in: group)
                return
            }
            guard let offset = embedded.firstIndex(where: { $0.id == trackID }), offset < group.options.count else {
                return
            }
            item.select(group.options[offset], in: group)
        }
    }

    private static func time(_ ticks: Ticks) -> CMTime {
        CMTime(value: ticks.rawValue, timescale: CMTimeScale(Ticks.perSecond))
    }

    private static func ticks(_ time: CMTime) -> Ticks? {
        guard time.isNumeric else {
            return nil
        }
        return Ticks(seconds: time.seconds)
    }
}

private final class AVPlayerRenderView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        backgroundColor = .black
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    /// AVPlayerLayer doesn't request match-content by itself the way AVPlayerViewController does.
    func applyDisplayCriteria(of asset: AVAsset) {
        window?.avDisplayManager.preferredDisplayCriteria = asset.preferredDisplayCriteria
    }

    func clearDisplayCriteria() {
        window?.avDisplayManager.preferredDisplayCriteria = nil
    }
}
