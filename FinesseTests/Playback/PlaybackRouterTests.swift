import Foundation
import Testing
@testable import FinEsse

private let directURL = URL(string: "http://server.invalid/direct")!
private let transcodeURL = URL(string: "http://server.invalid/master.m3u8")!

private func stream(
    _ index: Int,
    _ kind: MediaStreamKind,
    _ codec: String,
    bitDepth: Int? = nil,
    codecTag: String? = nil,
    external: Bool = false
) -> MediaStreamInfo {
    var info = MediaStreamInfo(index: index, kind: kind)
    info.codec = codec
    info.bitDepth = bitDepth
    info.codecTag = codecTag
    info.isExternal = external
    return info
}

private func source(
    container: String?,
    video: String = "h264",
    audio: String = "aac",
    subtitle: String? = nil,
    defaultSubtitle: Bool = false,
    direct: Bool = true,
    transcode: Bool = true
) -> PlaybackMediaSource {
    var result = PlaybackMediaSource(id: "source")
    result.container = container
    result.supportsDirectPlay = direct
    result.directPlayURL = directURL
    result.supportsTranscoding = transcode
    result.transcodingURL = transcode ? transcodeURL : nil
    result.streams = [stream(0, .video, video), stream(1, .audio, audio)]
    if let subtitle {
        result.streams.append(stream(2, .subtitle, subtitle))
        result.defaultSubtitleStreamIndex = defaultSubtitle ? 2 : nil
    }
    return result
}

@Suite struct PlaybackRouterTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var container: String
        var video: String
        var audio: String
        var subtitle: String?
        var expected: PlaybackEngineKind
        var testDescription: String {
            "\(container) \(video) \(audio) \(subtitle ?? "no subs") -> \(expected)"
        }
    }

    @Test(arguments: [
        Case(container: "mp4", video: "h264", audio: "aac", subtitle: nil, expected: .avPlayer),
        Case(container: "m4v", video: "hevc", audio: "eac3", subtitle: nil, expected: .avPlayer),
        Case(container: "mov", video: "hevc", audio: "ac3", subtitle: nil, expected: .avPlayer),
        Case(container: "mov,mp4,m4a,3gp,3g2,mj2", video: "h264", audio: "aac", subtitle: nil, expected: .avPlayer),
        Case(container: "mp4", video: "h264", audio: "aac", subtitle: "mov_text", expected: .avPlayer),
        Case(container: "mkv", video: "h264", audio: "aac", subtitle: nil, expected: .mpv),
        Case(container: "mkv", video: "h264", audio: "aac", subtitle: "mov_text", expected: .mpv),
        Case(container: "mp4", video: "h264", audio: "dts", subtitle: "mov_text", expected: .mpv),
        Case(container: "mkv", video: "h264", audio: "mlp", subtitle: nil, expected: .mpv),
        Case(container: "mov", video: "hevc", audio: "mlp", subtitle: nil, expected: .mpv),
        Case(container: "matroska,webm", video: "h264", audio: "aac", subtitle: nil, expected: .mpv),
        Case(container: "mp4", video: "h264", audio: "dts", subtitle: nil, expected: .mpv),
        Case(container: "mov", video: "hevc", audio: "truehd", subtitle: nil, expected: .mpv),
        Case(container: "mp4", video: "h264", audio: "aac", subtitle: "pgssub", expected: .mpv),
        Case(container: "mp4", video: "h264", audio: "aac", subtitle: "PGSSUB", expected: .mpv),
        Case(container: "mp4", video: "h264", audio: "aac", subtitle: "ass", expected: .mpv),
        Case(container: "mp4", video: "av1", audio: "aac", subtitle: nil, expected: .mpv),
        Case(container: "avi", video: "mpeg4", audio: "mp3", subtitle: nil, expected: .mpv),
        Case(container: "mkv", video: "mpeg2video", audio: "ac3", subtitle: "dvdsub", expected: .mpv),
    ])
    func directPlayRouting(_ test: Case) throws {
        let input = source(container: test.container, video: test.video, audio: test.audio,
                           subtitle: test.subtitle, defaultSubtitle: true)
        let route = try PlaybackRouter.route(sources: [input]).get()
        #expect(route.engine == test.expected)
        #expect(route.method == .directPlay)
        #expect(route.url == directURL)
    }

    @Test func unselectedSubtitleDoesNotForceMpv() throws {
        let input = source(container: "mp4", subtitle: "pgssub", defaultSubtitle: false)
        #expect(try PlaybackRouter.route(sources: [input]).get().engine == .avPlayer)
    }

    @Test func choosingSubtitleSwitchesEngineAndTurningItOffSwitchesBack() throws {
        let input = source(container: "mp4", subtitle: "pgssub", defaultSubtitle: true)
        #expect(try PlaybackRouter.route(sources: [input]).get().engine == .mpv)
        let off = try PlaybackRouter.route(sources: [input], subtitle: .off).get()
        #expect(off.engine == .avPlayer)
        #expect(off.subtitleStreamIndex == nil)
    }

    @Test func choosingAudioTrackDrivesRouting() throws {
        var input = source(container: "mp4", audio: "aac")
        input.streams.append(stream(3, .audio, "dts"))
        #expect(try PlaybackRouter.route(sources: [input]).get().engine == .avPlayer)
        let route = try PlaybackRouter.route(sources: [input], audioStreamIndex: 3).get()
        #expect(route.engine == .mpv)
        #expect(route.audioStreamIndex == 3)
    }

    @Test func externalSubtitleNeedsMpvEvenWhenCodecLooksNative() throws {
        var input = source(container: "mp4")
        input.streams.append(stream(2, .subtitle, "subrip", external: true))
        input.defaultSubtitleStreamIndex = 2
        #expect(try PlaybackRouter.route(sources: [input]).get().engine == .mpv)
    }

    @Test func highBitDepthLeavesAVPlayer() throws {
        var tenBit = source(container: "mp4")
        tenBit.streams[0] = stream(0, .video, "h264", bitDepth: 10)
        #expect(try PlaybackRouter.route(sources: [tenBit]).get().engine == .mpv)

    }

    @Test func hev1LeavesAVPlayerButHvc1Stays() throws {
        var hev1 = source(container: "mp4", video: "hevc")
        hev1.streams[0] = stream(0, .video, "hevc", bitDepth: 10, codecTag: "hev1")
        #expect(try PlaybackRouter.route(sources: [hev1]).get().engine == .mpv)

        var hvc1 = source(container: "mp4", video: "hevc")
        hvc1.streams[0] = stream(0, .video, "hevc", bitDepth: 10, codecTag: "hvc1")
        #expect(try PlaybackRouter.route(sources: [hvc1]).get().engine == .avPlayer)
    }

    @Test func transcodeIsLastResortAndPlaysOnAVPlayer() throws {
        let unknownCodec = source(container: "mkv", video: "theora")
        let route = try PlaybackRouter.route(sources: [unknownCodec]).get()
        #expect(route.engine == .avPlayer)
        #expect(route.method == .transcode)
        #expect(route.url == transcodeURL)

        let refused = source(container: "mp4", direct: false)
        #expect(try PlaybackRouter.route(sources: [refused]).get().method == .transcode)
    }

    @Test func aLaterDirectSourceBeatsTranscodingAnEarlierOne() throws {
        var first = source(container: "mkv", video: "theora")
        first.id = "first"
        var second = source(container: "mp4")
        second.id = "second"
        let route = try PlaybackRouter.route(sources: [first, second]).get()
        #expect(route.method == .directPlay)
        #expect(route.mediaSourceID == "second")
    }

    @Test func nothingPlayableIsAFailure() {
        #expect(PlaybackRouter.route(sources: []) == .failure(.noMediaSources))
        let input = source(container: "mkv", video: "theora", transcode: false)
        #expect(PlaybackRouter.route(sources: [input]) == .failure(.noPlayableSource))
    }
}
