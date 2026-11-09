import Foundation

/// Keeps one live connection open for the signed-in user and turns what the server says into
/// `ServerEvent`s on `events`. It pauses while the app is in the background, and on return or
/// after a gap it sends `catchUp`, because the server doesn't replay what was missed. Without a
/// connection it falls back to a `catchUp` every few minutes, which is the only timer it runs.
actor LiveUpdates {
    nonisolated let events: ServerEventHub
    private let source: (any LiveEventSource)?
    private let fallbackInterval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    private var loop: Task<Void, Never>?
    private var fallback: Task<Void, Never>?
    private var socket: (any LiveSocket)?
    private var stopped = false
    /// Whether the server has answered on the current connection.
    private(set) var isConnected = false
    /// Every connection opened, for tests.
    private(set) var connectionCount = 0

    init(
        source: (any LiveEventSource)?,
        events: ServerEventHub = ServerEventHub(),
        fallbackInterval: Duration = .seconds(300),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.source = source
        self.events = events
        self.fallbackInterval = fallbackInterval
        self.sleep = sleep
    }

    /// How long to wait before the next try, after this many failures in a row: 1, 2, 4 and so on
    /// up to a minute, so a server that's down isn't asked again and again.
    static func backoff(afterFailures failures: Int) -> Duration {
        .seconds(min(60, 1 << min(max(failures - 1, 0), 6)))
    }

    func start() {
        guard !stopped, loop == nil else { return }
        if source != nil {
            loop = Task { await run() }
        }
        fallback = Task { await runFallback() }
    }

    /// The app went to the background. Closes the connection rather than holding it open.
    func pause() {
        loop?.cancel()
        loop = nil
        fallback?.cancel()
        fallback = nil
        socket?.close()
        socket = nil
        isConnected = false
    }

    /// The app is back. Whatever changed meanwhile wasn't sent, so screens catch up.
    func resume() {
        guard !stopped, loop == nil, fallback == nil else { return }
        events.send(.catchUp)
        start()
    }

    /// Signed out or switched user. Nothing more is sent.
    func stop() {
        stopped = true
        pause()
    }

    private func run() async {
        guard let source else { return }
        var failures = 0
        var hadConnection = false
        while !Task.isCancelled {
            do {
                let opened = try await source.openLiveSocket()
                guard !Task.isCancelled else {
                    opened.socket.close()
                    return
                }
                socket = opened.socket
                connectionCount += 1
                try await read(opened.socket, userID: opened.userID) {
                    failures = 0
                    if hadConnection {
                        // Back after a gap, so anything sent meanwhile was missed.
                        self.events.send(.catchUp)
                    }
                    hadConnection = true
                }
            } catch {}
            // A pause or stop has already closed this connection, and a resume may have opened
            // the next one, so leave both alone.
            guard !Task.isCancelled else { return }
            socket?.close()
            socket = nil
            isConnected = false
            failures += 1
            try? await sleep(Self.backoff(afterFailures: failures))
        }
    }

    /// Reads until the connection fails or the loop is cancelled.
    private func read(_ socket: any LiveSocket, userID: String, onFirstAnswer: () -> Void) async throws {
        var keepAlive: Task<Void, Never>?
        defer { keepAlive?.cancel() }
        var answered = false
        while !Task.isCancelled {
            let text = try await socket.receive()
            if !answered {
                answered = true
                isConnected = true
                onFirstAnswer()
            }
            switch LiveMessage.parse(text, userID: userID) {
            case .forceKeepAlive(let seconds):
                // Half the server's limit, as Jellyfin's own clients do.
                keepAlive?.cancel()
                let interval = Duration.seconds(max(seconds / 2, 5))
                let sleep = sleep
                try? await socket.send(LiveMessage.keepAliveText)
                keepAlive = Task {
                    while !Task.isCancelled {
                        do {
                            try await sleep(interval)
                            try await socket.send(LiveMessage.keepAliveText)
                        } catch {
                            return
                        }
                    }
                }
            case .event(let event):
                events.send(event)
            case .keepAlive, .ignored:
                break
            }
        }
    }

    private func runFallback() async {
        while !Task.isCancelled {
            do {
                try await sleep(fallbackInterval)
            } catch {
                return
            }
            if !isConnected {
                events.send(.catchUp)
            }
        }
    }
}
