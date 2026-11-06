import Observation
import UIKit

enum PlaybackState: Hashable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case ended
    case failed(String)
}

/// An audio or subtitle track. `id` is the Jellyfin stream index on both engines.
struct PlaybackTrack: Identifiable, Hashable, Sendable {
    var id: Int
    var title: String
    var language: String?
    var codec: String?
    var isDefault: Bool
    var isForced: Bool
    var isExternal: Bool

    init(stream: MediaStreamInfo) {
        id = stream.index
        title = stream.displayTitle ?? stream.title ?? stream.language ?? "Track \(stream.index)"
        language = stream.language
        codec = stream.codec
        isDefault = stream.isDefault
        isForced = stream.isForced
        isExternal = stream.isExternal
    }
}

/// What an engine needs to start. Tracks come from the server's stream list, so both engines
/// show the same list and only differ in how they map a stream index to their own tracks.
struct PlaybackLoadRequest: Sendable {
    var url: URL
    var startPosition: Ticks
    var streams: [MediaStreamInfo]
    var audioStreamIndex: Int?
    var subtitleStreamIndex: Int?

    var audioTracks: [PlaybackTrack] {
        streams.filter { $0.kind == .audio }.map(PlaybackTrack.init)
    }

    var subtitleTracks: [PlaybackTrack] {
        streams.filter { $0.kind == .subtitle }.map(PlaybackTrack.init)
    }

    /// Where a stream sits in the file itself. Jellyfin numbers external subtitles in with the
    /// file's streams, usually first, so its index can be ahead of the file's. Nil for external ones.
    func fileStreamIndex(ofStream index: Int) -> Int? {
        guard let stream = streams.first(where: { $0.index == index }), !stream.isExternal else {
            return nil
        }
        return index - streams.filter { $0.isExternal && $0.index < index }.count
    }
}

/// The only way into an engine. Feature code never sees AVPlayer or mpv types.
@MainActor
protocol PlaybackEngine: AnyObject, Observable {
    var kind: PlaybackEngineKind { get }
    var state: PlaybackState { get }
    var position: Ticks { get }
    var duration: Ticks? { get }
    var audioTracks: [PlaybackTrack] { get }
    var subtitleTracks: [PlaybackTrack] { get }
    var selectedAudioTrackID: Int? { get }
    var selectedSubtitleTrackID: Int? { get }

    /// Starts loading, then plays from `request.startPosition`.
    func load(_ request: PlaybackLoadRequest)
    func play()
    func pause()
    func seek(to position: Ticks)
    /// False when the engine can't reach this track, so the session should move to another engine.
    func canSelectAudioTrack(id: Int) async -> Bool
    func selectAudioTrack(id: Int)
    /// Nil turns subtitles off.
    func selectSubtitleTrack(id: Int?)
    /// Stops for good. An engine is not reused after this.
    func stop()
    /// The view video is drawn into. Only `PlaybackSurface` calls this.
    func makeRenderView() -> UIView
}

extension PlaybackEngine {
    func canSelectAudioTrack(id: Int) async -> Bool {
        true
    }
}
