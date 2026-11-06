import Libmpv
import QuartzCore
import SwiftUI
import UIKit

// Plays the URL given as the first argument with the same mpv options as MPVEngine, and prints what
// mpv reports. Arguments: <url> [start seconds] [sid]. It proves the frameworks work, nothing more.

final class MetalView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
}

final class Player: @unchecked Sendable {
    let handle: OpaquePointer

    init?(layer: CAMetalLayer) {
        guard let handle = mpv_create() else { return nil }
        self.handle = handle
        var windowID = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &windowID)
        for (name, value) in [
            ("vo", "gpu-next"),
            ("gpu-api", "vulkan"),
            ("gpu-context", "moltenvk"),
            ("hwdec", "videotoolbox"),
            ("ao", "avfoundation,audiounit"),
            ("demuxer-max-bytes", "100MiB"),
            ("demuxer-max-back-bytes", "50MiB"),
        ] {
            mpv_set_option_string(handle, name, value)
        }
        // SPIKE_OPTS is name=value pairs separated by commas, for trying one option without a rebuild.
        for pair in (ProcessInfo.processInfo.environment["SPIKE_OPTS"] ?? "").split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { mpv_set_option_string(handle, parts[0], parts[1]) }
        }
        mpv_request_log_messages(handle, ProcessInfo.processInfo.environment["SPIKE_LOG"] ?? "info")
        guard mpv_initialize(handle) >= 0 else { return nil }
    }

    func string(_ name: String) -> String {
        guard let value = mpv_get_property_string(handle, name) else { return "unavailable" }
        defer { mpv_free(value) }
        return String(cString: value)
    }

    func load(_ url: String, start: String, sid: String?) {
        mpv_set_property_string(handle, "start", start)
        if let sid {
            mpv_set_property_string(handle, "sid", sid)
        }
        var pointers: [UnsafePointer<CChar>?] = ["loadfile", url].map { UnsafePointer(strdup($0)) }
        pointers.append(nil)
        mpv_command(handle, &pointers)
    }

    func drainEvents() {
        while true {
            guard let event = mpv_wait_event(handle, -1)?.pointee else { continue }
            switch event.event_id {
            case MPV_EVENT_SHUTDOWN:
                return
            case MPV_EVENT_LOG_MESSAGE:
                let message = event.data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
                print("[mpv \(String(cString: message.prefix))] \(String(cString: message.text))", terminator: "")
            case MPV_EVENT_FILE_LOADED:
                print("SPIKE file loaded")
            case MPV_EVENT_PLAYBACK_RESTART:
                print("SPIKE playback restart")
            case MPV_EVENT_END_FILE:
                let end = event.data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                print("SPIKE end file reason \(end.reason.rawValue) error \(String(cString: mpv_error_string(end.error)))")
            default:
                break
            }
        }
    }
}

struct PlayerView: UIViewRepresentable {
    func makeUIView(context: Context) -> MetalView {
        let view = MetalView(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: MetalView, context: Context) {
        // Starts once the view has a window, so the layer has its final size.
        guard Spike.player == nil else { return }
        view.layoutIfNeeded()
        Spike.start(layer: view.metalLayer)
    }
}

@MainActor
enum Spike {
    static var player: Player?

    static func start(layer: CAMetalLayer) {
        setvbuf(stdout, nil, _IOLBF, 0)
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.count > 1, let player = Player(layer: layer) else {
            print("SPIKE no url, or mpv failed to start")
            return
        }
        Self.player = player
        Thread.detachNewThread { player.drainEvents() }
        player.load(arguments[1], start: arguments.count > 2 ? arguments[2] : "0", sid: arguments.count > 3 ? arguments[3] : nil)
        // SPIKE_SWITCH_SID selects a subtitle track at runtime, the way MPVEngine does, rather than before loading.
        if let sid = ProcessInfo.processInfo.environment["SPIKE_SWITCH_SID"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                print("SPIKE switching to sid \(sid)")
                mpv_set_property_string(player.handle, "sid", sid)
            }
        }
        // Counts distinct subtitle start times, because a screenshot can land between subtitles.
        var seenStarts = Set<String>()
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            let start = player.string("sub-start")
            if start != "unavailable", seenStarts.insert(start).inserted {
                print("SPIKE sub event \(seenStarts.count) at \(start)")
            }
        }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            print("SPIKE state pos=\(player.string("time-pos")) vo=\(player.string("current-vo")) ao=\(player.string("current-ao")) hwdec=\(player.string("hwdec-current")) vcodec=\(player.string("video-codec")) acodec=\(player.string("audio-codec-name")) sid=\(player.string("sid")) substart=\(player.string("sub-start")) subend=\(player.string("sub-end")) subtext=\(player.string("sub-text").prefix(60))")
        }
    }
}

@main
struct DepsSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            PlayerView().ignoresSafeArea()
        }
    }
}
