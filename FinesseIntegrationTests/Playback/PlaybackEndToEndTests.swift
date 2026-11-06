import Foundation
import Testing
import UIKit
@testable import FinEsse

/// Plays real media as the test user and reads the saved position back from the server.
/// Tolerates any library contents and puts each item's saved position back afterwards.
private enum LiveServer {
    static let environment = ProcessInfo.processInfo.environment
    static let url = environment["JELLYFIN_URL"].flatMap(URL.init(string:))
    static let username = environment["JELLYFIN_USERNAME"]
    static let password = environment["JELLYFIN_PASSWORD"]
    static let isConfigured = url != nil && username != nil && password != nil

    /// Its own DeviceId, because signing in again on a DeviceId revokes that device's token.
    static func signedInClient() async throws -> LiveJellyfinClient {
        let client = LiveJellyfinClient(
            serverURL: try #require(url),
            device: DeviceIdentity(
                clientName: "Finesse Playback Tests",
                clientVersion: "1.0",
                deviceName: "Simulator",
                deviceID: "finesse-playback-tests"
            )
        )
        _ = try await client.signIn(username: try #require(username), password: try #require(password))
        return client
    }
}

@MainActor
@Suite(.serialized, .enabled(if: LiveServer.isConfigured, "JELLYFIN_* variables not set"))
struct PlaybackEndToEndTests {
    /// Long enough to review a screenshot of the running engine.
    private let watchTime = Duration.seconds(15)

    /// The first unwatched item that the router sends to `engine` with direct play.
    private func findItem(
        for engine: PlaybackEngineKind,
        client: LiveJellyfinClient
    ) async throws -> MediaItem? {
        let profile = DeviceProfileBuilder.make()
        for startIndex in stride(from: 0, to: 2000, by: 100) {
            let page = try await client.items(ItemQuery(kinds: [.episode, .movie], startIndex: startIndex, limit: 100))
            for item in page.items where item.userState.playbackPosition == .zero && !item.userState.isPlayed {
                guard let runTime = item.runTime, runTime.seconds > 300 else {
                    continue
                }
                let info = try await client.playbackInfo(PlaybackInfoRequest(itemID: item.id, deviceProfile: profile))
                if case .success(let route) = PlaybackRouter.route(sources: info.mediaSources),
                   route.engine == engine, route.method == .directPlay {
                    return item
                }
            }
            if page.items.isEmpty {
                break
            }
        }
        return nil
    }

    private func wait(
        timeout: Duration = .seconds(45),
        until condition: @MainActor () -> Bool
    ) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        return condition()
    }

    private func show(_ engine: any PlaybackEngine) -> UIView? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first
        guard let window else {
            return nil
        }
        let view = engine.makeRenderView()
        view.frame = window.bounds
        window.addSubview(view)
        return view
    }

    private func playAndConfirmResume(_ kind: PlaybackEngineKind) async throws {
        let client = try await LiveServer.signedInClient()
        guard let item = try await findItem(for: kind, client: client), let runTime = item.runTime else {
            Issue.record("No unwatched direct play item routes to \(kind)")
            return
        }
        let start = Ticks(seconds: runTime.seconds * 0.3)
        let session = PlaybackSession(client: client, itemID: item.id, startPosition: start, reportInterval: .seconds(2))

        try await session.start()
        let engine = try #require(session.engine)
        #expect(engine.kind == kind)
        let view = show(engine)
        defer { view?.removeFromSuperview() }

        let played = try await wait {
            engine.state == .playing && engine.position.seconds > start.seconds + 2
        }
        #expect(played, "state \(String(describing: engine.state)), position \(engine.position.seconds), start \(start.seconds)")
        #expect(engine.duration != nil)

        try await Task.sleep(for: watchTime)
        let stoppedAt = engine.position
        #expect(stoppedAt.seconds > start.seconds + 10)
        await session.stop()

        let saved = try await client.item(id: item.id).userState.playbackPosition
        #expect(abs(saved.seconds - stoppedAt.seconds) < 3, "saved \(saved.seconds), stopped at \(stoppedAt.seconds)")

        // Stopping this early in the runtime makes the server clear the position again.
        try await client.reportPlaybackStopped(PlaybackReport(
            itemID: item.id,
            position: .zero,
            playMethod: .directPlay
        ))
    }

    @Test func avPlayerPlaysAndResumePositionReachesServer() async throws {
        try await playAndConfirmResume(.avPlayer)
    }

    @Test func mpvPlaysAndResumePositionReachesServer() async throws {
        try await playAndConfirmResume(.mpv)
    }
}
