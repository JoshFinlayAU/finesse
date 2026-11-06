import Foundation
import Testing
@testable import FinEsse

@Suite struct DeviceProfileBuilderTests {
    private func names(_ list: String?) -> Set<String> {
        Set((list ?? "").split(separator: ",").map(String.init))
    }

    @Test func directPlayProfilesMirrorEachEngine() {
        let profile = DeviceProfileBuilder.make()
        #expect(profile.directPlayProfiles.count == EngineCapabilities.routingOrder.count)
        for (entry, engine) in zip(profile.directPlayProfiles, EngineCapabilities.routingOrder) {
            #expect(entry.type == .video)
            #expect(names(entry.container) == engine.containers)
            #expect(names(entry.videoCodec) == engine.videoCodecs)
            #expect(names(entry.audioCodec) == engine.audioCodecs)
        }
    }

    @Test func changingCapabilitiesChangesTheProfile() {
        var engine = EngineCapabilities.mpv
        engine.containers = ["mkv"]
        engine.audioCodecs = ["opus"]
        let profile = DeviceProfileBuilder.make(engines: [engine])
        #expect(profile.directPlayProfiles.first?.container == "mkv")
        #expect(profile.directPlayProfiles.first?.audioCodec == "opus")
    }

    @Test func everySubtitleTheEnginesShowIsDeclared() {
        let profile = DeviceProfileBuilder.make()
        let embedded = Set(profile.subtitleProfiles.filter { $0.method == "Embed" }.map(\.format))
        let external = Set(profile.subtitleProfiles.filter { $0.method == "External" }.map(\.format))
        #expect(embedded == EngineCapabilities.avPlayer.embeddedSubtitleCodecs.union(EngineCapabilities.mpv.embeddedSubtitleCodecs))
        #expect(external == EngineCapabilities.mpv.externalSubtitleCodecs)
    }

    @Test func transcodeTargetIsSomethingAVPlayerPlays() throws {
        let transcode = try #require(DeviceProfileBuilder.make().transcodingProfiles.first)
        #expect(transcode.protocolName == "hls")
        #expect(names(transcode.videoCodec).isSubset(of: EngineCapabilities.avPlayer.videoCodecs))
        #expect(names(transcode.audioCodec).isSubset(of: EngineCapabilities.avPlayer.audioCodecs))
    }

    @Test func bitrateLimitsDoNotForceTranscoding() {
        let profile = DeviceProfileBuilder.make()
        #expect(profile.maxStaticBitrate == DeviceProfileBuilder.maxBitrate)
        #expect(profile.maxStreamingBitrate == DeviceProfileBuilder.maxBitrate)
    }

    @Test func encodesWithJellyfinFieldNames() throws {
        let data = try JSONEncoder().encode(DeviceProfileBuilder.make())
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["DirectPlayProfiles"] != nil)
        #expect(json["TranscodingProfiles"] != nil)
        #expect(json["SubtitleProfiles"] != nil)
    }
}
