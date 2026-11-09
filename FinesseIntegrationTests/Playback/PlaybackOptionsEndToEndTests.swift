import AVFoundation
import Foundation
import Testing
import UIKit
@testable import FinEsse

private enum LiveServer {
    static let environment = ProcessInfo.processInfo.environment
    static let isConfigured = environment["JELLYFIN_URL"] != nil
        && environment["JELLYFIN_USERNAME"] != nil
        && environment["JELLYFIN_PASSWORD"] != nil

    static func signedInClient() async throws -> LiveJellyfinClient {
        let client = LiveJellyfinClient(
            serverURL: try #require(environment["JELLYFIN_URL"].flatMap(URL.init(string:))),
            device: DeviceIdentity(
                clientName: "Finesse Playback Tests",
                clientVersion: "1.0",
                deviceName: "Simulator",
                deviceID: "finesse-playback-options-tests"
            )
        )
        _ = try await client.signIn(
            username: try #require(environment["JELLYFIN_USERNAME"]),
            password: try #require(environment["JELLYFIN_PASSWORD"])
        )
        return client
    }
}

/// Options on real engines and real media. The fakes only record what they're told, so this is what
/// shows speed, picture mode, subtitle size and delays really change something.
@MainActor
@Suite(.serialized, .enabled(if: LiveServer.isConfigured, "JELLYFIN_* variables not set"), .disabled(if: TestPlanScope.leavesOutPlayback, "Left to Playback.xctestplan"))
struct PlaybackOptionsEndToEndTests {
    /// An MP4 with mov_text subtitles that AVPlayer plays, with regular dialogue from 15 minutes in.
    private let movText = "75c2da7ae8730a3faa40e7b6f09eefee"

    private func waitUntil(timeout: Duration = .seconds(45), _ condition: @MainActor () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        return condition()
    }

    /// Runs `body` with the item playing on screen, then stops and clears the saved position.
    private func withPlayback(
        engines: [EngineCapabilities],
        expecting kind: PlaybackEngineKind,
        _ body: @MainActor (PlaybackSession, any PlaybackEngine, UIView) async throws -> Void
    ) async throws {
        let client = try await LiveServer.signedInClient()
        let session = PlaybackSession(client: client, itemID: movText, startPosition: Ticks(seconds: 900), engines: engines)
        try await session.start()
        let engine = try #require(session.engine)
        #expect(engine.kind == kind)
        #expect(engine.isSilent, "\(engine.kind) should play silently in the simulator")
        let window = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first)
        let view = engine.makeRenderView()
        view.frame = window.bounds
        window.addSubview(view)
        defer { view.removeFromSuperview() }
        #expect(try await waitUntil { engine.state == .playing && engine.position.seconds > 901 })

        var failure: (any Error)?
        do {
            try await body(session, engine, view)
        } catch {
            failure = error
        }
        await session.stop()
        try await client.reportPlaybackStopped(PlaybackReport(itemID: movText, position: .zero, playMethod: .directPlay))
        if let failure {
            throw failure
        }
    }

    private func subtitleLabel(in view: UIView) throws -> UILabel {
        try #require(view.subviews.compactMap { $0 as? UILabel }.first)
    }

    private func secondsPlayed(by engine: any PlaybackEngine, in wait: Duration) async throws -> Double {
        let before = engine.position.seconds
        try await Task.sleep(for: wait)
        return engine.position.seconds - before
    }

    // MARK: Speed

    @Test(arguments: [true, false])
    func speedReallyChangesHowFastTimePasses(onAVPlayer: Bool) async throws {
        try await withPlayback(engines: onAVPlayer ? EngineCapabilities.routingOrder : [.mpv], expecting: onAVPlayer ? .avPlayer : .mpv) { session, engine, _ in
            var options = session.options
            options.rate = 2
            try await session.setOptions(options)
            try await Task.sleep(for: .seconds(2))
            let double = try await secondsPlayed(by: engine, in: .seconds(8))
            print("SPEED \(engine.kind) 2x played \(double) in 8s")
            #expect(double > 12, "2x should play well over 8 seconds in 8: \(double)")

            options.rate = 1
            try await session.setOptions(options)
            try await Task.sleep(for: .seconds(2))
            let normal = try await secondsPlayed(by: engine, in: .seconds(8))
            print("SPEED \(engine.kind) 1x played \(normal) in 8s")
            #expect(normal < 10, "Back at normal speed: \(normal)")
        }
    }

    // MARK: Picture

    @Test func pictureModeReachesAVPlayersLayer() async throws {
        try await withPlayback(engines: EngineCapabilities.routingOrder, expecting: .avPlayer) { session, _, view in
            let layer = try #require(view.layer as? AVPlayerLayer)
            #expect(layer.videoGravity == .resizeAspect)
            var options = session.options
            options.pictureMode = .fill
            try await session.setOptions(options)
            #expect(layer.videoGravity == .resizeAspectFill)
            options.pictureMode = .stretch
            try await session.setOptions(options)
            #expect(layer.videoGravity == .resize)
        }
    }

    @Test func mpvReallyHoldsEveryOption() async throws {
        try await withPlayback(engines: [.mpv], expecting: .mpv) { session, engine, _ in
            let mpv = try #require(engine as? MPVEngine)
            @MainActor func number(_ name: String) -> Double? { mpv.property(name).flatMap(Double.init) }
            var options = session.options
            options.pictureMode = .fill
            options.subtitleScale = 1.5
            options.subtitleRaise = 20
            options.subtitleDelay = 1.5
            options.audioDelay = 0.3
            try await session.setOptions(options)
            #expect(number("panscan") == 1)
            #expect(number("sub-scale") == 1.5)
            #expect(number("sub-pos") == 80)
            #expect(number("sub-delay") == 1.5)
            #expect(number("audio-delay") == 0.3)

            options.pictureMode = .stretch
            try await session.setOptions(options)
            #expect(number("panscan") == 0)
            #expect(mpv.property("keepaspect") == "no")
        }
    }

    /// A subtitle offset moves which line shows at a given moment, which is the point of it.
    @Test func aSubtitleOffsetReallyChangesWhatShowsOnMpv() async throws {
        try await withPlayback(engines: [.mpv], expecting: .mpv) { session, engine, _ in
            let mpv = try #require(engine as? MPVEngine)
            try await session.selectSubtitleTrack(id: 2)
            #expect(try await waitUntil { !(mpv.property("sub-text") ?? "").isEmpty }, "Should reach a line of dialogue")
            await session.pause()
            let at = engine.position
            try await Task.sleep(for: .seconds(1))
            let line = mpv.property("sub-text") ?? ""
            try #require(!line.isEmpty)

            var options = session.options
            options.subtitleDelay = 10
            try await session.setOptions(options)
            await session.seek(to: at)
            try await Task.sleep(for: .seconds(2))
            let moved = mpv.property("sub-text") ?? ""
            print("OFFSET at \(at.seconds): '\(line.prefix(30))' became '\(moved.prefix(30))'")
            #expect(moved != line)

            options.subtitleDelay = 0
            try await session.setOptions(options)
            await session.seek(to: at)
            try await Task.sleep(for: .seconds(2))
            #expect(mpv.property("sub-text") == line, "No offset puts the same line back")
        }
    }

    @Test func aDelayOnAVPlayerReallyMovesToMpvAndCarriesOn() async throws {
        try await withPlayback(engines: EngineCapabilities.routingOrder, expecting: .avPlayer) { session, first, _ in
            let position = first.position
            var options = session.options
            options.audioDelay = 0.5
            try await session.setOptions(options)
            let moved = try #require(session.engine as? MPVEngine)
            #expect(try await waitUntil { moved.state == .playing })
            #expect(moved.property("audio-delay").flatMap(Double.init) == 0.5)
            #expect(abs(moved.position.seconds - position.seconds) < 30)
            let played = try await secondsPlayed(by: moved, in: .seconds(4))
            #expect(played > 1, "Should keep playing on mpv")
        }
    }

    // MARK: Our subtitle drawing on AVPlayer

    /// The label is ours, so this reads what's really on it rather than what was asked for.
    @Test func avPlayerSubtitlesReallyDrawAndFollowTheOptions() async throws {
        try await withPlayback(engines: EngineCapabilities.routingOrder, expecting: .avPlayer) { session, engine, view in
            let av = try #require(engine as? AVPlayerEngine)
            let label = try subtitleLabel(in: view)
            try await session.selectSubtitleTrack(id: 2)

            #expect(try await waitUntil { !av.subtitleText.isEmpty || av.drawsSubtitlesNatively }, "AVPlayer should hand over a line")
            // tvOS 26 hands over nothing, so AVPlayer draws them itself, unstyled. Ours must stay out of the way.
            if av.drawsSubtitlesNatively {
                #expect(ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27, "Only tvOS 26 should need AVPlayer's own drawing")
                try await Task.sleep(for: .seconds(2))
                view.layoutIfNeeded()
                #expect(label.isHidden, "AVPlayer draws the line, so ours must not show it too")
                return
            }
            @MainActor func showing() -> Bool {
                view.layoutIfNeeded()
                return label.attributedText?.string.isEmpty == false && !label.isHidden && label.alpha > 0
            }
            #expect(try await waitUntil(timeout: .seconds(10)) { showing() })
            #expect(view.bounds.contains(label.frame), "\(label.frame) should be on screen")
            #expect(label.frame.height > 0)

            // Reading an attribute of an empty string traps, so an empty label counts as no size.
            @MainActor func fontSize() -> CGFloat {
                guard let text = label.attributedText, text.length > 0 else { return 0 }
                return (text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize ?? 0
            }
            let normalSize = fontSize()
            #expect(normalSize > 0)

            var options = session.options
            options.subtitleScale = 1.5
            try await session.setOptions(options)
            #expect(try await waitUntil(timeout: .seconds(20)) { showing() })
            #expect(abs(fontSize() - normalSize * 1.5) < 0.5, "Size should follow the option")

            // The bottom edge is where the line sits, whatever its length.
            options.subtitleScale = 1
            try await session.setOptions(options)
            #expect(try await waitUntil(timeout: .seconds(20)) { showing() })
            let normalBottom = label.frame.maxY
            options.subtitleRaise = 20
            try await session.setOptions(options)
            #expect(try await waitUntil(timeout: .seconds(20)) { showing() })
            #expect(label.frame.maxY < normalBottom - view.bounds.height * 0.15, "Position should follow the option")

            // A background hugs the words rather than filling a fixed width.
            options.subtitleRaise = 0
            options.subtitleBackgroundColor = SubtitleColor(red: 0, green: 0, blue: 0, alpha: 1)
            try await session.setOptions(options)
            #expect(try await waitUntil(timeout: .seconds(30)) {
                showing() && (label.attributedText?.string.count ?? 99) < 35
            }, "Should reach a short line")
            #expect(label.frame.width < view.bounds.width * 0.7, "\(label.frame.width) of \(view.bounds.width)")

            try await session.selectSubtitleTrack(id: nil)
            view.layoutIfNeeded()
            #expect(av.subtitleText.isEmpty)
            #expect(label.isHidden, "No subtitle should leave no box behind")
        }
    }
}
