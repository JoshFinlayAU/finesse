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
    /// What the user asked for before the item was ready, which starting up has to respect.
    @ObservationIgnored private var wantsPause = false
    @ObservationIgnored private weak var renderView: AVPlayerRenderView?
    @ObservationIgnored private var options = PlaybackOptions()
    /// AVPlayer ignores text style rules on an MP4's subtitles, so it hands them over to be drawn here.
    @ObservationIgnored private let subtitleOutput = AVPlayerItemLegibleOutput(mediaSubtypesForNativeRepresentation: [])
    @ObservationIgnored private let subtitleReceiver = SubtitleReceiver()
    /// What's showing now. Internal so a test can read it.
    @ObservationIgnored private(set) var subtitleText = ""

    init() {
        subtitleOutput.suppressesPlayerRendering = true
        subtitleOutput.setDelegate(subtitleReceiver, queue: .main)
        subtitleReceiver.onText = { [weak self] text in
            self?.subtitleText = text
            self?.renderView?.showSubtitle(text)
        }
    }

    func load(_ request: PlaybackLoadRequest) {
        state = .loading
        position = request.startPosition
        audioTracks = request.audioTracks
        subtitleTracks = request.subtitleTracks
        selectedAudioTrackID = request.audioStreamIndex
        selectedSubtitleTrackID = request.subtitleStreamIndex
        pendingStart = request.startPosition > .zero ? request.startPosition : nil
        hasStarted = false
        wantsPause = false

        let item = AVPlayerItem(url: request.url)
        item.audioTimePitchAlgorithm = .timeDomain
        item.add(subtitleOutput)
        observe(item)
        player.replaceCurrentItem(with: item)
    }

    func play() {
        wantsPause = false
        player.play()
    }

    func pause() {
        wantsPause = true
        player.pause()
    }

    func seek(to position: Ticks) {
        self.position = position
        // Too early to seek. Starting up goes to this position instead.
        guard hasStarted else {
            pendingStart = position
            return
        }
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
        subtitleText = ""
        renderView?.showSubtitle("")
        applySelection(.legible, trackID: id, tracks: subtitleTracks)
    }

    func apply(_ options: PlaybackOptions) {
        self.options = options
        player.defaultRate = Float(options.rate)
        if player.rate != 0 {
            player.rate = Float(options.rate)
        }
        renderView?.apply(options)
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
        view.apply(options)
        view.showSubtitle(subtitleText)
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
                    Task { @MainActor in self?.startPlaying() }
                }
            } else {
                startPlaying()
            }
        case .failed:
            state = .failed(item.error?.localizedDescription ?? "Playback failed")
        default:
            break
        }
    }

    /// Staying paused from before the item was ready changes nothing, so no status change will
    /// come to report it. It has to be set here.
    private func startPlaying() {
        if wantsPause {
            state = .paused
        } else {
            player.play()
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

/// Delivered on the main queue, as asked for in `setDelegate`.
private final class SubtitleReceiver: NSObject, AVPlayerItemLegibleOutputPushDelegate {
    var onText: (@MainActor (String) -> Void)?

    func legibleOutput(
        _ output: AVPlayerItemLegibleOutput,
        didOutputAttributedStrings strings: [NSAttributedString],
        nativeSampleBuffers nativeSamples: [Any],
        forItemTime itemTime: CMTime
    ) {
        let text = strings.map(\.string).joined(separator: "\n")
        MainActor.assumeIsolated { onText?(text) }
    }
}

private final class AVPlayerRenderView: UIView {
    private let subtitleLabel = UILabel()
    private var subtitleScale = 1.0
    private var subtitleRaise = 0
    private var subtitleText = ""
    private var subtitleColor = UIColor.white
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        backgroundColor = .black
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        subtitleLabel.clipsToBounds = true
        subtitleLabel.layer.cornerRadius = 8
        addSubview(subtitleLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    func apply(_ options: PlaybackOptions) {
        switch options.pictureMode {
        case .fit: playerLayer.videoGravity = .resizeAspect
        case .fill: playerLayer.videoGravity = .resizeAspectFill
        case .stretch: playerLayer.videoGravity = .resize
        }
        subtitleScale = options.subtitleScale
        subtitleRaise = options.subtitleRaise
        subtitleColor = options.subtitleTextColor.map(Self.color) ?? .white
        subtitleLabel.backgroundColor = options.subtitleBackgroundColor.map(Self.color) ?? .clear
        setNeedsLayout()
    }

    func showSubtitle(_ text: String) {
        subtitleText = text
        setNeedsLayout()
    }

    private static func color(_ color: SubtitleColor) -> UIColor {
        UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    /// Sizes follow the screen, as mpv's do, so the two engines look alike.
    override func layoutSubviews() {
        super.layoutSubviews()
        // A soft shadow keeps white text readable on a white frame. A stroke leaves marks across the letters.
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black
        shadow.shadowBlurRadius = bounds.height * 0.005
        shadow.shadowOffset = CGSize(width: 0, height: bounds.height * 0.001)
        subtitleLabel.attributedText = NSAttributedString(string: subtitleText, attributes: [
            .font: UIFont.systemFont(ofSize: bounds.height * 0.042 * subtitleScale, weight: .medium),
            .foregroundColor: subtitleColor,
            .shadow: shadow,
        ])
        let width = bounds.width * 0.8
        let height = subtitleLabel.sizeThatFits(CGSize(width: width, height: bounds.height)).height
        let bottom = bounds.height * (0.95 - Double(subtitleRaise) / 100)
        subtitleLabel.frame = CGRect(x: (bounds.width - width) / 2, y: bottom - height, width: width, height: height)
    }

    /// AVPlayerLayer doesn't request match-content by itself the way AVPlayerViewController does.
    func applyDisplayCriteria(of asset: AVAsset) {
        window?.avDisplayManager.preferredDisplayCriteria = asset.preferredDisplayCriteria
    }

    func clearDisplayCriteria() {
        window?.avDisplayManager.preferredDisplayCriteria = nil
    }
}
