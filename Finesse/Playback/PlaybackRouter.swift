import Foundation

/// How one media source will be played.
struct PlaybackRoute: Hashable, Sendable {
    var engine: PlaybackEngineKind
    var method: PlayMethod
    var url: URL
    var mediaSourceID: String
    var liveStreamID: String?
    var audioStreamIndex: Int?
    var subtitleStreamIndex: Int?
}

enum PlaybackRoutingFailure: Error, Hashable, Sendable {
    case noMediaSources
    case noPlayableSource
}

enum SubtitleChoice: Hashable, Sendable {
    case sourceDefault
    case off
    case stream(Int)
}

/// The one place engine choice is made. AVPlayer first, then mpv, then the server's
/// transcode, which is the last resort because transcoding is expensive on the server.
enum PlaybackRouter {
    static func route(
        sources: [PlaybackMediaSource],
        audioStreamIndex: Int? = nil,
        subtitle: SubtitleChoice = .sourceDefault,
        engines: [EngineCapabilities] = EngineCapabilities.routingOrder
    ) -> Result<PlaybackRoute, PlaybackRoutingFailure> {
        guard !sources.isEmpty else {
            return .failure(.noMediaSources)
        }
        for source in sources {
            if let route = directRoute(source, audioStreamIndex, subtitle, engines) {
                return .success(route)
            }
        }
        for source in sources {
            if let route = transcodeRoute(source, audioStreamIndex, subtitle) {
                return .success(route)
            }
        }
        return .failure(.noPlayableSource)
    }

    private static func directRoute(
        _ source: PlaybackMediaSource,
        _ audioStreamIndex: Int?,
        _ subtitle: SubtitleChoice,
        _ engines: [EngineCapabilities]
    ) -> PlaybackRoute? {
        guard source.supportsDirectPlay, let url = source.directPlayURL else {
            return nil
        }
        let video = source.streams.first { $0.kind == .video }
        let audio = selectedAudio(source, audioStreamIndex)
        let text = selectedSubtitle(source, subtitle)
        let engine = engines.first {
            $0.canPlay(container: source.container, video: video, audio: audio, subtitle: text)
        }
        guard let engine else {
            return nil
        }
        return PlaybackRoute(
            engine: engine.engine,
            method: .directPlay,
            url: url,
            mediaSourceID: source.id,
            liveStreamID: source.liveStreamID,
            audioStreamIndex: audio?.index,
            subtitleStreamIndex: text?.index
        )
    }

    private static func transcodeRoute(
        _ source: PlaybackMediaSource,
        _ audioStreamIndex: Int?,
        _ subtitle: SubtitleChoice
    ) -> PlaybackRoute? {
        guard source.supportsTranscoding, let url = source.transcodingURL else {
            return nil
        }
        return PlaybackRoute(
            engine: .avPlayer,
            method: .transcode,
            url: url,
            mediaSourceID: source.id,
            liveStreamID: source.liveStreamID,
            audioStreamIndex: selectedAudio(source, audioStreamIndex)?.index,
            subtitleStreamIndex: selectedSubtitle(source, subtitle)?.index
        )
    }

    private static func selectedAudio(_ source: PlaybackMediaSource, _ index: Int?) -> MediaStreamInfo? {
        let audio = source.streams.filter { $0.kind == .audio }
        let wanted = index ?? source.defaultAudioStreamIndex
        return audio.first { $0.index == wanted } ?? audio.first
    }

    private static func selectedSubtitle(_ source: PlaybackMediaSource, _ choice: SubtitleChoice) -> MediaStreamInfo? {
        let wanted: Int?
        switch choice {
        case .off: wanted = nil
        case .stream(let index): wanted = index
        case .sourceDefault: wanted = source.defaultSubtitleStreamIndex
        }
        guard let wanted else {
            return nil
        }
        return source.streams.first { $0.kind == .subtitle && $0.index == wanted }
    }
}
