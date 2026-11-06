import Foundation

enum PlaybackEngineKind: String, Hashable, Sendable {
    case avPlayer
    case mpv
}

/// What one engine can play. The router and the device profile both read this,
/// so what we ask the server for can't drift from what we route.
/// All values are lowercase names as Jellyfin reports them.
struct EngineCapabilities: Hashable, Sendable {
    var engine: PlaybackEngineKind
    var containers: Set<String>
    var videoCodecs: Set<String>
    var audioCodecs: Set<String>
    /// Subtitle codecs the engine can show when they are embedded in the media.
    var embeddedSubtitleCodecs: Set<String>
    /// Subtitle codecs the engine can load from a separate URL.
    var externalSubtitleCodecs: Set<String>
    /// Highest bit depth by video codec. A codec with no entry has no limit.
    var maxVideoBitDepth: [String: Int] = [:]
    /// Sample entries the engine refuses for a codec, such as hev1 on AVPlayer.
    var rejectedVideoCodecTags: [String: Set<String>] = [:]

    func canPlay(
        container: String?,
        video: MediaStreamInfo?,
        audio: MediaStreamInfo?,
        subtitle: MediaStreamInfo?
    ) -> Bool {
        guard let container, Self.names(container).contains(where: containers.contains) else {
            return false
        }
        if let video {
            guard let codec = video.codec?.lowercased(), videoCodecs.contains(codec) else {
                return false
            }
            if let limit = maxVideoBitDepth[codec], let depth = video.bitDepth, depth > limit {
                return false
            }
            if let tag = video.codecTag?.lowercased(), rejectedVideoCodecTags[codec]?.contains(tag) == true {
                return false
            }
        }
        if let audio {
            guard let codec = audio.codec?.lowercased(), audioCodecs.contains(codec) else {
                return false
            }
        }
        if let subtitle {
            guard let codec = subtitle.codec?.lowercased() else {
                return false
            }
            let supported = subtitle.isExternal ? externalSubtitleCodecs : embeddedSubtitleCodecs
            guard supported.contains(codec) else {
                return false
            }
        }
        return true
    }

    /// Jellyfin can report a container as a comma separated list, such as "mov,mp4,m4a".
    private static func names(_ container: String) -> [String] {
        container.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

extension EngineCapabilities {
    /// Containers and codecs AVPlayer plays natively over progressive HTTP on tvOS.
    /// FLAC, MPEG-TS and AV1 are left out because they don't hold across the hardware we support.
    static let avPlayer = EngineCapabilities(
        engine: .avPlayer,
        containers: ["mp4", "m4v", "mov"],
        videoCodecs: ["h264", "hevc"],
        audioCodecs: ["aac", "ac3", "eac3", "mp3", "alac"],
        embeddedSubtitleCodecs: ["mov_text"],
        externalSubtitleCodecs: [],
        maxVideoBitDepth: ["h264": 8, "hevc": 10],
        rejectedVideoCodecTags: ["hevc": ["hev1"]]
    )

    /// Taken from the decoders and demuxers present in our own tvOS mpv and FFmpeg build.
    /// AVPlayer stays first in the routing order, so this only takes mov_text and MLP files it can't play.
    static let mpv = EngineCapabilities(
        engine: .mpv,
        containers: ["mkv", "webm", "mp4", "m4v", "mov", "avi", "ts", "m2ts", "mpegts", "mpg", "mpeg", "vob", "asf", "wmv", "ogv", "ogg", "flv"],
        videoCodecs: ["h264", "hevc", "av1", "vp8", "vp9", "mpeg1video", "mpeg2video", "mpeg4", "vc1", "wmv3"],
        audioCodecs: ["aac", "ac3", "eac3", "dts", "dca", "truehd", "mlp", "mp2", "mp3", "flac", "alac", "opus", "vorbis", "pcm_s16le", "pcm_s24le"],
        embeddedSubtitleCodecs: ["ass", "ssa", "subrip", "srt", "webvtt", "mov_text", "pgssub", "dvdsub", "dvbsub"],
        externalSubtitleCodecs: ["ass", "ssa", "subrip", "srt", "vtt", "webvtt"]
    )

    /// Engines in the order the router tries them.
    static let routingOrder: [EngineCapabilities] = [.avPlayer, .mpv]
}
