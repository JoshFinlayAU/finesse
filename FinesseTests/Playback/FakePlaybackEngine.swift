import Foundation
import Observation
import UIKit
@testable import FinEsse

/// Lets a test hold an async call open, so something else can really happen during it.
actor TestGate {
    private var hasArrived = false
    private var isOpen = false
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    private var passengers: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        hasArrived = true
        arrivals.forEach { $0.resume() }
        arrivals.removeAll()
        if !isOpen {
            await withCheckedContinuation { passengers.append($0) }
        }
    }

    func waitForArrival() async {
        if !hasArrived {
            await withCheckedContinuation { arrivals.append($0) }
        }
    }

    func open() {
        isOpen = true
        passengers.forEach { $0.resume() }
        passengers.removeAll()
    }
}

/// Behaves like the real engines in the way that matters here: asking to pause or play doesn't
/// change `state` straight away. Call `settle()` for the moment the engine catches up.
@MainActor
@Observable
final class FakePlaybackEngine: PlaybackEngine {
    let kind: PlaybackEngineKind
    var state = PlaybackState.idle
    var position = Ticks.zero
    var duration: Ticks?
    var audioTracks: [PlaybackTrack] = []
    var subtitleTracks: [PlaybackTrack] = []
    var selectedAudioTrackID: Int?
    var selectedSubtitleTrackID: Int?
    var loaded: PlaybackLoadRequest?
    var seeks: [Ticks] = []
    var stopped = false
    var unreachableAudio: Set<Int> = []
    var canSelectGate: TestGate?
    var applied: [PlaybackOptions] = []
    var playCalls = 0
    private var pendingState: PlaybackState?

    init(kind: PlaybackEngineKind) {
        self.kind = kind
    }

    func load(_ request: PlaybackLoadRequest) {
        loaded = request
        position = request.startPosition
        audioTracks = request.audioTracks
        subtitleTracks = request.subtitleTracks
        selectedAudioTrackID = request.audioStreamIndex
        selectedSubtitleTrackID = request.subtitleStreamIndex
        duration = Ticks(seconds: 1000)
        state = .loading
        pendingState = .playing
    }

    func settle() {
        if let pendingState {
            state = pendingState
        }
        pendingState = nil
    }

    func play() {
        playCalls += 1
        pendingState = .playing
    }
    func pause() { pendingState = .paused }
    func seek(to position: Ticks) {
        seeks.append(position)
        self.position = position
    }
    func canSelectAudioTrack(id: Int) async -> Bool {
        await canSelectGate?.pass()
        return !unreachableAudio.contains(id)
    }
    func selectAudioTrack(id: Int) { selectedAudioTrackID = id }
    func selectSubtitleTrack(id: Int?) { selectedSubtitleTrackID = id }
    func apply(_ options: PlaybackOptions) { applied.append(options) }
    func stop() { stopped = true }
    func makeRenderView() -> UIView { UIView() }
}

@MainActor
func letOtherTasksRun() async {
    for _ in 0..<50 {
        await Task.yield()
    }
}
