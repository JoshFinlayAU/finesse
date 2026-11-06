import Foundation

/// Reports start, periodic progress and stop to the server for one playback, whichever
/// engine is playing. Failed reports are dropped: a network blip must not stop playback,
/// and the next report carries the current position anyway.
@MainActor
final class PlaybackProgressReporter {
    struct Snapshot: Hashable, Sendable {
        var position: Ticks
        var isPaused: Bool
        var audioStreamIndex: Int?
        var subtitleStreamIndex: Int?
    }

    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let client: any JellyfinClient
    private let itemID: String
    private var playSessionID: String?
    private let interval: Duration
    private let sleep: Sleep
    private let snapshot: @MainActor () -> Snapshot
    private var route: PlaybackRoute
    private var startReport: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var isStarted = false
    private var isStopped = false

    init(
        client: any JellyfinClient,
        itemID: String,
        playSessionID: String?,
        route: PlaybackRoute,
        interval: Duration = .seconds(10),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        snapshot: @escaping @MainActor () -> Snapshot
    ) {
        self.client = client
        self.itemID = itemID
        self.playSessionID = playSessionID
        self.route = route
        self.interval = interval
        self.sleep = sleep
        self.snapshot = snapshot
    }

    func start() async {
        guard !isStarted, !isStopped else {
            return
        }
        isStarted = true
        let report = report(snapshot())
        // Its own task, so a stop arriving meanwhile can wait for this and can't overtake it.
        let startReport = Task { [client] in
            _ = try? await client.reportPlaybackStart(report)
        }
        self.startReport = startReport
        await startReport.value
        guard !isStopped else {
            return
        }
        ticker = Task { [weak self, interval, sleep] in
            while !Task.isCancelled {
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard let self else {
                    return
                }
                await self.reportProgress()
            }
        }
    }

    /// Also call this straight after a pause, seek or track change so the server isn't left behind.
    func reportProgress() async {
        guard isStarted, !isStopped else {
            return
        }
        await startReport?.value
        guard !isStopped else {
            return
        }
        try? await client.reportPlaybackProgress(report(snapshot()))
    }

    /// The engine can switch mid-playback when the user picks a track only the other engine plays.
    /// A rebuilt transcode also has a new play session, which the server needs named to end its job.
    func updateRoute(_ route: PlaybackRoute, playSessionID: String?) {
        self.route = route
        self.playSessionID = playSessionID
    }

    func stop() async {
        guard isStarted, !isStopped else {
            return
        }
        isStopped = true
        ticker?.cancel()
        ticker = nil
        await startReport?.value
        try? await client.reportPlaybackStopped(report(snapshot()))
    }

    private func report(_ snapshot: Snapshot) -> PlaybackReport {
        PlaybackReport(
            itemID: itemID,
            mediaSourceID: route.mediaSourceID,
            playSessionID: playSessionID,
            liveStreamID: route.liveStreamID,
            position: snapshot.position,
            isPaused: snapshot.isPaused,
            playMethod: route.method,
            audioStreamIndex: snapshot.audioStreamIndex,
            subtitleStreamIndex: snapshot.subtitleStreamIndex
        )
    }
}
