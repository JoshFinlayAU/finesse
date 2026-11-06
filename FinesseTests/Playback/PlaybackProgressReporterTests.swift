import Foundation
import Testing
@testable import FinEsse

/// Lets a test run one reporting interval at a time.
private actor ManualClock {
    private var waiting: [CheckedContinuation<Void, Error>] = []
    private var sleepers: [CheckedContinuation<Void, Never>] = []

    func sleep() async throws {
        try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
            sleepers.forEach { $0.resume() }
            sleepers.removeAll()
        }
    }

    func waitForSleeper() async {
        if !waiting.isEmpty {
            return
        }
        await withCheckedContinuation { sleepers.append($0) }
    }

    func tick() {
        guard !waiting.isEmpty else {
            return
        }
        waiting.removeFirst().resume()
    }
}

@MainActor
@Suite struct PlaybackProgressReporterTests {
    private let route = PlaybackRoute(
        engine: .mpv,
        method: .directPlay,
        url: URL(string: "http://server.invalid/direct")!,
        mediaSourceID: "source"
    )

    private final class Position {
        var snapshot = PlaybackProgressReporter.Snapshot(position: .zero, isPaused: false)
    }

    private func makeReporter(
        _ client: InMemoryJellyfinClient,
        _ position: Position,
        clock: ManualClock = ManualClock()
    ) -> PlaybackProgressReporter {
        PlaybackProgressReporter(
            client: client,
            itemID: "item",
            playSessionID: "session",
            route: route,
            sleep: { _ in try await clock.sleep() },
            snapshot: { position.snapshot }
        )
    }

    /// The fake only accepts reports from a signed-in client.
    private func signedInClient() async throws -> InMemoryJellyfinClient {
        let client = InMemoryJellyfinClient()
        _ = try await client.signIn(username: "Test User", password: "password")
        return client
    }

    @Test func secondsBecomeTicksAtTenMillionPerSecond() {
        #expect(Ticks(seconds: 1).rawValue == 10_000_000)
        #expect(Ticks(seconds: 90.5).rawValue == 905_000_000)
        #expect(Ticks(rawValue: 36_000_000_000).seconds == 3600)
        #expect(Ticks(seconds: .nan) == .zero)
    }

    @Test func reportsStartCarryingRouteAndPosition() async throws {
        let client = try await signedInClient()
        let position = Position()
        position.snapshot = .init(position: Ticks(seconds: 120), isPaused: false, audioStreamIndex: 1, subtitleStreamIndex: 2)
        let reporter = makeReporter(client, position)

        await reporter.start()

        let start = await client.startReports.first
        #expect(await client.startReports.count == 1)
        #expect(start?.itemID == "item")
        #expect(start?.mediaSourceID == "source")
        #expect(start?.playSessionID == "session")
        #expect(start?.playMethod == .directPlay)
        #expect(start?.position.rawValue == 1_200_000_000)
        #expect(start?.audioStreamIndex == 1)
        #expect(start?.subtitleStreamIndex == 2)
        await reporter.stop()
    }

    @Test func reportsProgressEachInterval() async throws {
        let client = try await signedInClient()
        let position = Position()
        let clock = ManualClock()
        let reporter = makeReporter(client, position, clock: clock)
        await reporter.start()

        await clock.waitForSleeper()
        position.snapshot.position = Ticks(seconds: 10)
        await clock.tick()
        await clock.waitForSleeper()
        #expect(await client.progressReports.last?.position == Ticks(seconds: 10))

        position.snapshot.position = Ticks(seconds: 20)
        position.snapshot.isPaused = true
        await clock.tick()
        await clock.waitForSleeper()
        #expect(await client.progressReports.count == 2)
        #expect(await client.progressReports.last?.position == Ticks(seconds: 20))
        #expect(await client.progressReports.last?.isPaused == true)
        await reporter.stop()
    }

    @Test func stopReportsFinalPositionOnceAndEndsProgress() async throws {
        let client = try await signedInClient()
        let position = Position()
        let reporter = makeReporter(client, position)
        await reporter.start()

        position.snapshot.position = Ticks(seconds: 42)
        await reporter.stop()
        await reporter.stop()
        await reporter.reportProgress()

        #expect(await client.stopReports.count == 1)
        #expect(await client.stopReports.first?.position == Ticks(seconds: 42))
        #expect(await client.progressReports.isEmpty)
    }

    @Test func stopBeforeStartReportsNothing() async throws {
        let client = try await signedInClient()
        let reporter = makeReporter(client, Position())
        await reporter.stop()
        #expect(await client.stopReports.isEmpty)
    }

    @Test func aFailedReportDoesNotEndReporting() async throws {
        let client = try await signedInClient()
        let reporter = makeReporter(client, Position())
        await client.configure { $0.failure = .notFound }
        await reporter.start()
        await reporter.reportProgress()
        await client.configure { $0.failure = nil }
        await reporter.reportProgress()
        await reporter.stop()
        #expect(await client.progressReports.count == 1)
        #expect(await client.stopReports.count == 1)
    }

    @Test func routeChangeAppliesToLaterReports() async throws {
        let client = try await signedInClient()
        let reporter = makeReporter(client, Position())
        await reporter.start()
        var switched = route
        switched.method = .transcode
        reporter.updateRoute(switched)
        await reporter.reportProgress()
        #expect(await client.progressReports.last?.playMethod == .transcode)
        await reporter.stop()
    }
}
