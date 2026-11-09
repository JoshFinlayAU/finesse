import SwiftUI

extension EnvironmentValues {
    /// What the signed-in user's live connection reports. Outside the signed-in shell nothing is sent.
    @Entry var serverEvents = ServerEventHub()
}

extension View {
    /// Refreshes this screen when the server reports a change, while the screen is showing. A burst
    /// of changes, such as a library scan, makes one refresh once it has gone quiet. Nothing happens
    /// while `isPaused`, which screens set while the player covers them; they refresh as it closes.
    func refreshesOnServerChanges(isPaused: Bool = false, _ refresh: @escaping @MainActor () async -> Void) -> some View {
        modifier(LiveRefreshModifier(isPaused: isPaused, refresh: refresh))
    }
}

private struct LiveRefreshModifier: ViewModifier {
    @Environment(\.serverEvents) private var events
    let isPaused: Bool
    let refresh: @MainActor () async -> Void

    func body(content: Content) -> some View {
        content.task(id: isPaused) {
            guard !isPaused else { return }
            let debouncer = RefreshDebouncer(refresh: refresh)
            for await _ in events.stream() {
                debouncer.signal()
            }
            debouncer.cancel()
        }
    }
}

/// Waits for changes to stop for `quiet` before refreshing, but no longer than `longest` after the
/// first, so a scan that keeps going still shows its progress.
@MainActor
final class RefreshDebouncer {
    private let quiet: Duration
    private let longest: Duration
    private let refresh: @MainActor () async -> Void
    private var pending: Task<Void, Never>?
    private var lastSignal = ContinuousClock.now
    private var firstSignal = ContinuousClock.now

    init(quiet: Duration = .seconds(3), longest: Duration = .seconds(15), refresh: @escaping @MainActor () async -> Void) {
        self.quiet = quiet
        self.longest = longest
        self.refresh = refresh
    }

    func signal() {
        let now = ContinuousClock.now
        lastSignal = now
        guard pending == nil else { return }
        firstSignal = now
        pending = Task { [weak self] in
            while let self, !Task.isCancelled {
                let due = min(self.lastSignal + self.quiet, self.firstSignal + self.longest)
                if ContinuousClock.now >= due { break }
                try? await Task.sleep(until: due, clock: .continuous)
            }
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            await self.refresh()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
