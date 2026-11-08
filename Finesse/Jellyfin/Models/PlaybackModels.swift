import Foundation

// The device profile keeps Jellyfin's wire field names so it encodes directly into the
// PlaybackInfo request. The playback layer decides the values; this layer only sends them.

enum DlnaProfileKind: String, Hashable, Sendable, Codable {
    case audio = "Audio"
    case video = "Video"
    case photo = "Photo"
    case subtitle = "Subtitle"
}

struct DirectPlayProfile: Hashable, Sendable, Codable {
    var type: DlnaProfileKind
    var container: String
    var videoCodec: String?
    var audioCodec: String?

    enum CodingKeys: String, CodingKey {
        case type = "Type", container = "Container", videoCodec = "VideoCodec", audioCodec = "AudioCodec"
    }
}

struct TranscodingProfile: Hashable, Sendable, Codable {
    var type: DlnaProfileKind
    var container: String
    var videoCodec: String?
    var audioCodec: String?
    /// "hls" or "http".
    var protocolName: String
    var context: String = "Streaming"
    var maxAudioChannels: String?
    var minSegments: Int?
    var breakOnNonKeyFrames: Bool?

    enum CodingKeys: String, CodingKey {
        case type = "Type", container = "Container", videoCodec = "VideoCodec", audioCodec = "AudioCodec"
        case protocolName = "Protocol", context = "Context", maxAudioChannels = "MaxAudioChannels"
        case minSegments = "MinSegments", breakOnNonKeyFrames = "BreakOnNonKeyFrames"
    }
}

struct SubtitleProfile: Hashable, Sendable, Codable {
    var format: String
    /// "Embed", "External", "Encode" or "Hls".
    var method: String
    var container: String?

    enum CodingKeys: String, CodingKey {
        case format = "Format", method = "Method", container = "Container"
    }
}

struct ProfileCondition: Hashable, Sendable, Codable {
    var condition: String
    var property: String
    var value: String?
    var isRequired: Bool = false

    enum CodingKeys: String, CodingKey {
        case condition = "Condition", property = "Property", value = "Value", isRequired = "IsRequired"
    }
}

struct CodecProfile: Hashable, Sendable, Codable {
    /// "Video", "VideoAudio" or "Audio".
    var type: String
    var codec: String?
    var container: String?
    var conditions: [ProfileCondition] = []
    var applyConditions: [ProfileCondition] = []

    enum CodingKeys: String, CodingKey {
        case type = "Type", codec = "Codec", container = "Container"
        case conditions = "Conditions", applyConditions = "ApplyConditions"
    }
}

struct DeviceProfile: Hashable, Sendable, Codable {
    var name: String?
    var maxStreamingBitrate: Int?
    var maxStaticBitrate: Int?
    var directPlayProfiles: [DirectPlayProfile] = []
    var transcodingProfiles: [TranscodingProfile] = []
    var subtitleProfiles: [SubtitleProfile] = []
    var codecProfiles: [CodecProfile] = []

    enum CodingKeys: String, CodingKey {
        case name = "Name", maxStreamingBitrate = "MaxStreamingBitrate", maxStaticBitrate = "MaxStaticBitrate"
        case directPlayProfiles = "DirectPlayProfiles", transcodingProfiles = "TranscodingProfiles"
        case subtitleProfiles = "SubtitleProfiles", codecProfiles = "CodecProfiles"
    }
}

struct PlaybackInfoRequest: Hashable, Sendable {
    var itemID: String
    var mediaSourceID: String?
    var startPosition: Ticks?
    var audioStreamIndex: Int?
    var subtitleStreamIndex: Int?
    var maxStreamingBitrate: Int?
    var deviceProfile: DeviceProfile
    var enableDirectPlay = true
    var enableDirectStream = true
    var enableTranscoding = true
}

enum MediaStreamKind: Hashable, Sendable {
    case video
    case audio
    case subtitle
    case other(String)
}

struct MediaStreamInfo: Hashable, Sendable {
    var index: Int
    var kind: MediaStreamKind
    var codec: String?
    /// For example hvc1 or hev1. AVPlayer refuses hev1-tagged HEVC, so the router needs it.
    var codecTag: String?
    var language: String?
    var title: String?
    var displayTitle: String?
    var isDefault = false
    var isForced = false
    var isExternal = false
    var isTextSubtitle = false
    /// Absolute URL for an external subtitle, when the server provides one.
    var deliveryURL: URL?
    var channels: Int?
    var bitRate: Int?
    var width: Int?
    var height: Int?
    var frameRate: Double?
    var bitDepth: Int?
    var profile: String?
    /// For example SDR, HDR10, DOVI, as the server reports it.
    var videoRangeType: String?
}

/// One playable version of an item. URLs are absolute and may carry the access token, so never log them.
struct PlaybackMediaSource: Identifiable, Hashable, Sendable {
    var id: String
    var name: String?
    var container: String?
    var size: Int64?
    var bitRate: Int?
    var runTime: Ticks?
    var supportsDirectPlay = false
    var supportsDirectStream = false
    var supportsTranscoding = false
    var directPlayURL: URL?
    var transcodingURL: URL?
    var transcodingSubProtocol: String?
    var eTag: String?
    var liveStreamID: String?
    var defaultAudioStreamIndex: Int?
    var defaultSubtitleStreamIndex: Int?
    var streams: [MediaStreamInfo] = []
}

struct PlaybackInfo: Hashable, Sendable {
    var playSessionID: String?
    var mediaSources: [PlaybackMediaSource] = []
    /// Set by the server when it refuses playback, for example "NotAllowed" or "NoCompatibleStream".
    var errorCode: String?
}

enum PlayMethod: String, Hashable, Sendable {
    case directPlay = "DirectPlay"
    case directStream = "DirectStream"
    case transcode = "Transcode"
}

/// One start, progress or stop report. Send the same `playSessionID` for all reports of a playback.
struct PlaybackReport: Hashable, Sendable {
    var itemID: String
    var mediaSourceID: String?
    var playSessionID: String?
    var liveStreamID: String?
    var position: Ticks
    var isPaused = false
    var isMuted = false
    var playMethod: PlayMethod
    var audioStreamIndex: Int?
    var subtitleStreamIndex: Int?
}
