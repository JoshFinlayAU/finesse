import Foundation

/// The read-only media details in the player's info panel.
enum PlayerInfo {
    struct Row: Identifiable, Hashable {
        var title: String
        var value: String
        var id: String { title }
    }

    static func rows(
        source: PlaybackMediaSource?,
        route: PlaybackRoute?,
        audioIndex: Int?,
        subtitleIndex: Int?
    ) -> [Row] {
        var rows: [Row] = []
        func add(_ title: String, _ value: String?) {
            if let value, !value.isEmpty {
                rows.append(Row(title: title, value: value))
            }
        }
        if let route {
            add("Playing", route.method == .directPlay ? "Direct from the file" : "Converted by the server")
            add("Player", route.engine == .avPlayer ? "AVPlayer" : "mpv")
        }
        let streams = source?.streams ?? []
        if let video = streams.first(where: { $0.kind == .video }) {
            add("Video", videoDescription(video))
            add("Dynamic range", video.videoRangeType)
        }
        add("Audio", streams.first { $0.kind == .audio && $0.index == audioIndex }.flatMap(describe))
        add("Subtitles", subtitleIndex == nil ? "Off" : streams.first { $0.index == subtitleIndex }.flatMap(describe))
        add("Container", source?.container)
        add("Bitrate", source?.bitRate.map(bitrate))
        add("File size", source?.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) })
        return rows
    }

    static func bitrate(_ bits: Int) -> String {
        bits >= 1_000_000
            ? String(format: "%.1f Mbps", Double(bits) / 1_000_000)
            : "\(bits / 1000) kbps"
    }

    private static func describe(_ stream: MediaStreamInfo) -> String? {
        stream.displayTitle ?? stream.title ?? stream.language ?? stream.codec
    }

    private static func videoDescription(_ video: MediaStreamInfo) -> String {
        var parts: [String] = []
        if let codec = video.codec { parts.append(codec.uppercased()) }
        if let width = video.width, let height = video.height { parts.append("\(width) x \(height)") }
        if let rate = video.frameRate { parts.append(String(format: "%.3g fps", rate)) }
        if let depth = video.bitDepth { parts.append("\(depth)-bit") }
        return parts.joined(separator: ", ")
    }
}
