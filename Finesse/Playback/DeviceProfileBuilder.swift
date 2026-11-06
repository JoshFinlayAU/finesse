import Foundation

/// Builds the profile sent with PlaybackInfo from the same tables the router uses.
/// The server only transcodes in software, so nothing here should push it to transcode
/// a file one of our engines can direct play.
enum DeviceProfileBuilder {
    /// High enough that a bitrate limit never turns direct play into a transcode.
    static let maxBitrate = 400_000_000

    static func make(engines: [EngineCapabilities] = EngineCapabilities.routingOrder) -> DeviceProfile {
        DeviceProfile(
            name: "Finesse",
            maxStreamingBitrate: maxBitrate,
            maxStaticBitrate: maxBitrate,
            directPlayProfiles: engines.map(directPlayProfile),
            transcodingProfiles: [transcodingProfile],
            subtitleProfiles: subtitleProfiles(engines),
            codecProfiles: []
        )
    }

    private static func directPlayProfile(_ engine: EngineCapabilities) -> DirectPlayProfile {
        DirectPlayProfile(
            type: .video,
            container: joined(engine.containers),
            videoCodec: joined(engine.videoCodecs),
            audioCodec: joined(engine.audioCodecs)
        )
    }

    /// Played by AVPlayer, so it has to stay within what AVPlayer takes over HLS.
    private static let transcodingProfile = TranscodingProfile(
        type: .video,
        container: "ts",
        videoCodec: "h264",
        audioCodec: "aac,ac3,eac3",
        protocolName: "hls",
        minSegments: 1,
        breakOnNonKeyFrames: true
    )

    private static func subtitleProfiles(_ engines: [EngineCapabilities]) -> [SubtitleProfile] {
        let embedded = Set(engines.flatMap(\.embeddedSubtitleCodecs))
        let external = Set(engines.flatMap(\.externalSubtitleCodecs))
        var profiles = embedded.sorted().map { SubtitleProfile(format: $0, method: "Embed") }
        profiles += external.sorted().map { SubtitleProfile(format: $0, method: "External") }
        // A transcode goes to AVPlayer, which can't draw these, so the server has to burn them in.
        profiles += embedded.subtracting(EngineCapabilities.avPlayer.embeddedSubtitleCodecs).sorted().map {
            SubtitleProfile(format: $0, method: "Encode")
        }
        return profiles
    }

    private static func joined(_ names: Set<String>) -> String {
        names.sorted().joined(separator: ",")
    }
}
