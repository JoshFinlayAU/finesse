import SwiftUI
import UIKit

/// The full-screen player. Start it with `AppNavigator.play(_:resumeFrom:)`.
struct PlayerScreen: View {
    let request: PlaybackRequest
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.jellyfinClient) private var client
    @State private var model: PlayerModel?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                PlayerContent(model: model) {
                    navigator.activePlayback = nil
                }
            }
        }
        .task {
            guard model == nil else {
                return
            }
            #if DEBUG
            if SeededPlayback.isEnabled {
                await SeededPlayback.prepare(client: client, request: request)
                model = PlayerModel(
                    client: client,
                    request: request,
                    preferenceStore: SeededPlayback.preferenceStore,
                    makeEngine: { SeededPlaybackEngine(kind: $0) }
                )
                return
            }
            #endif
            model = PlayerModel(client: client, request: request)
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            // Covers any dismissal that didn't come through Back.
            if let model { Task { await model.exit() } }
        }
    }
}

private struct PlayerContent: View {
    let model: PlayerModel
    let onFinished: () -> Void
    @FocusState private var focus: PlayerFocus?
    /// A move that took focus somewhere isn't also a swipe that should close the bar.
    @State private var lastFocusChange = Date.distantPast

    var body: some View {
        ZStack {
            if let engine = model.engine {
                PlaybackSurface(engine: engine)
                    .id(ObjectIdentifier(engine))
                    .ignoresSafeArea()
            }
            switch model.phase {
            case .loading:
                LoadingStateView()
            case .playing:
                playing
            case .upNext(let next, let secondsLeft):
                PlayerUpNextCard(
                    item: next,
                    secondsLeft: secondsLeft,
                    onPlay: { Task { await model.playNext() } },
                    onCancel: { model.cancelUpNext() }
                )
            case .failed(let message):
                ErrorStateView(message: message) {
                    Task { await model.start() }
                }
            case .finished:
                EmptyView()
            }
        }
        .background {
            RemoteTouchRecognizer(
                onPan: { fraction in Task { await model.send(.panned(fraction)) } },
                onSwipe: moved
            )
        }
        .onMoveCommand(perform: moved)
        .onExitCommand { Task { await model.backPressed() } }
        .onPlayPauseCommand { Task { await model.send(.playPause) } }
        .task { await model.start() }
        .task {
            while !Task.isCancelled {
                await model.tick()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .task(id: upNextID) {
            guard upNextID != nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await model.upNextTick()
            }
        }
        .onChange(of: model.phase) { _, phase in
            switch phase {
            case .finished: onFinished()
            case .playing: placeFocus()
            default: break
            }
        }
        .onChange(of: model.skip) { _, skip in
            // Takes focus only when nothing else is in use, so it never interrupts the controls.
            if skip != nil, model.controls.mode == .hidden {
                focus = .skip
            } else if skip == nil, focus == .skip {
                placeFocus()
            }
        }
        .onChange(of: model.controls.mode) { old, _ in
            placeFocus(leaving: old)
        }
        .onChange(of: focus) { _, _ in
            lastFocusChange = .now
            Task { await model.send(.activity) }
        }
        .alert(
            "Couldn't Change That",
            isPresented: Binding(get: { model.trackError != nil }, set: { if !$0 { model.clearTrackError() } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.trackError ?? "")
        }
        .environment(\.colorScheme, .dark)
    }

    private var upNextID: String? {
        if case .upNext(let next, _) = model.phase { next.id } else { nil }
    }

    private var playing: some View {
        ZStack {
            PlayerRemoteSurface(model: model, focus: $focus) {
                Task { await model.send(.click) }
            }
            if model.isBuffering {
                ProgressView()
                    .controlSize(.large)
            }
            VStack(alignment: .trailing, spacing: 24) {
                Spacer()
                if let panel = model.controls.panel {
                    PlayerPanelView(panel: panel, model: model, focus: $focus)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let skip = model.skip, model.controls.scrub == nil {
                    Button(skip.title) {
                        Task { await model.skipPressed() }
                    }
                    .buttonStyle(.glass)
                    .focused($focus, equals: .skip)
                    .accessibilityIdentifier("skipSegment")
                }
                if model.controls.hasButtons {
                    PlayerHUDBar(model: model, focus: $focus)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let scrub = model.controls.scrub {
                    PlayerScrubBar(model: model, scrub: scrub)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if model.isPaused {
                    PlayerPausedPill(position: model.displayPosition)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
        }
        .animation(.smooth(duration: 0.35), value: animationKey)
        .onAppear { placeFocus() }
    }

    /// Changes with what's showing but not with every step of a scrub, which has its own motion.
    private var animationKey: String {
        switch model.controls.mode {
        case .hidden: model.isPaused ? "paused" : "hidden"
        case .bar: "bar"
        case .panel(let panel): panel.rawValue
        case .scrubbing: "scrubbing"
        }
    }

    private func moved(_ direction: MoveCommandDirection) {
        let event: PlayerControls.Event
        switch direction {
        case .up: event = .swipeUp
        case .left: event = .moveLeft
        case .right: event = .moveRight
        case .down:
            guard Date.now.timeIntervalSince(lastFocusChange) > 0.25 else { return }
            event = .swipeDown
        @unknown default: return
        }
        Task { await model.send(event) }
    }

    /// New targets don't exist or can't take focus until this update has finished.
    private func placeFocus(leaving old: PlayerControls.Mode? = nil) {
        let target: PlayerFocus
        switch model.controls.mode {
        case .hidden:
            target = model.skip == nil ? .surface : .skip
        case .scrubbing:
            target = .surface
        case .bar:
            if case .panel(let panel)? = old {
                target = .panelButton(panel)
            } else {
                target = .main
            }
        case .panel(let panel):
            target = .panelRow(model.initialRowID(of: panel))
        }
        Task { @MainActor in
            await Task.yield()
            focus = target
        }
    }
}

/// Invisible and full screen. It has focus while nothing else shows, so the first click lands here.
private struct PlayerRemoteSurface: View {
    let model: PlayerModel
    let focus: FocusState<PlayerFocus?>.Binding
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(PlayerInvisibleButtonStyle())
        .focused(focus, equals: .surface)
        .disabled(model.controls.hasButtons)
        .ignoresSafeArea()
        .accessibilityIdentifier("transportBar")
        .accessibilityValue(accessibilityValue)
    }

    /// XCUITest can't see focus inside the full-screen cover, so this says what's showing.
    private var accessibilityValue: String {
        var parts = [PlayerTime.format(model.displayPosition)]
        if model.isPaused { parts.append("paused") }
        switch model.controls.mode {
        case .hidden: parts.append("hidden")
        case .bar: parts.append("bar")
        case .panel(let panel): parts.append("panel \(panel.rawValue)")
        case .scrubbing: parts.append("scrubbing")
        }
        switch focus.wrappedValue {
        case .main: parts.append("focus main")
        case .panelButton(let panel): parts.append("focus \(panel.rawValue)")
        case .skip: parts.append("focus skip")
        default: break
        }
        return parts.joined(separator: ", ")
    }
}

private struct PlayerInvisibleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct PlayerUpNextCard: View {
    let item: MediaItem
    let secondsLeft: Int
    let onPlay: () -> Void
    let onCancel: () -> Void
    @FocusState private var playHasFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Up Next")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(item.cardTitle)
                .font(.title2.weight(.semibold))
            if let subtitle = item.cardSubtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Text("Playing in \(secondsLeft) seconds")
                .font(.callout.monospacedDigit())
            HStack(spacing: 24) {
                Button("Play Now", action: onPlay)
                    .focused($playHasFocus)
                    .accessibilityIdentifier("upNextPlay")
                Button("Cancel", action: onCancel)
                    .accessibilityIdentifier("upNextCancel")
            }
            .buttonStyle(.glass)
        }
        .padding(48)
        .glassEffect(in: .rect(cornerRadius: 40))
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(60)
        .onAppear { playHasFocus = true }
    }
}

enum PlayerTime {
    static func format(_ ticks: Ticks) -> String {
        let total = max(Int(ticks.seconds), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
