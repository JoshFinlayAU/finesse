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
            if model == nil {
                model = PlayerModel(client: client, request: request)
            }
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
    private enum Focus: Hashable {
        case transport
        case skip
        case upNextPlay
    }

    let model: PlayerModel
    let onFinished: () -> Void
    @FocusState private var focus: Focus?
    @State private var scrubCommit: Task<Void, Never>?

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
                .focused($focus, equals: .upNextPlay)
            case .failed(let message):
                ErrorStateView(message: message) {
                    Task { await model.start() }
                }
            case .finished:
                EmptyView()
            }
        }
        .background { RemotePanRecognizer(onPan: pan, onEnded: scheduleScrubCommit) }
        .onExitCommand { Task { await model.backPressed() } }
        .onPlayPauseCommand { Task { await model.togglePlayPause() } }
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
            case .upNext: focus = .upNextPlay
            case .playing: focus = .transport
            default: break
            }
        }
        .onChange(of: model.skip) { _, skip in
            // Takes focus only when nothing else is in use, so it never interrupts the controls.
            if skip != nil, !model.controlsVisible {
                focus = .skip
            } else if skip == nil, focus == .skip {
                focus = .transport
            }
        }
        .onChange(of: focus) { _, focus in
            model.keepControlsVisible = focus != .transport && focus != .skip
        }
        .alert(
            "Couldn't Change Track",
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
        VStack(alignment: .trailing, spacing: 24) {
            Spacer()
            if model.isBuffering {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
            if let skip = model.skip {
                Button(skip.title) {
                    Task { await model.skipPressed() }
                }
                .buttonStyle(.glass)
                .focused($focus, equals: .skip)
                .accessibilityIdentifier("skipSegment")
            }
            PlayerTransportBar(model: model) {
                Task { await model.selectPressed() }
            } onMove: { direction in
                move(direction)
            }
            .focused($focus, equals: .transport)
            .defaultFocus($focus, .transport)
            if model.controlsVisible {
                PlayerTrackButtons(model: model)
            }
        }
        .padding(60)
    }

    private func move(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            model.scrub(bySeconds: -PlayerModel.clickScrubSeconds)
            scheduleScrubCommit()
        case .right:
            model.scrub(bySeconds: PlayerModel.clickScrubSeconds)
            scheduleScrubCommit()
        default:
            model.noteActivity()
        }
    }

    private func pan(_ fraction: Double) {
        guard focus == .transport else { return }
        scrubCommit?.cancel()
        model.scrub(byPanFraction: fraction)
    }

    /// Lets repeated presses add up before the engine has to seek.
    private func scheduleScrubCommit() {
        scrubCommit?.cancel()
        scrubCommit = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await model.commitScrub()
        }
    }
}

/// Always focusable, even when invisible, so the first press after the controls hide still lands here.
private struct PlayerTransportBar: View {
    let model: PlayerModel
    let onSelect: () -> Void
    let onMove: (MoveCommandDirection) -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.item.cardTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                if let subtitle = model.item.cardSubtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ProgressView(value: fraction)
                    .tint(.white)
                HStack {
                    Text(PlayerTime.format(model.displayPosition))
                    Spacer()
                    if model.isPaused {
                        Image(systemName: "pause.fill")
                    }
                    Spacer()
                    Text(model.duration.map(PlayerTime.format) ?? "")
                }
                .font(.callout.monospacedDigit())
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: .rect(cornerRadius: 32))
            .opacity(model.controlsVisible ? 1 : 0)
        }
        .buttonStyle(PlayerBarButtonStyle())
        .onMoveCommand(perform: onMove)
        .accessibilityIdentifier("transportBar")
        .accessibilityValue(PlayerTime.format(model.displayPosition))
    }

    private var fraction: Double {
        guard let duration = model.duration?.seconds, duration > 0 else {
            return 0
        }
        return min(max(model.displayPosition.seconds / duration, 0), 1)
    }
}

/// Keeps the bar from lifting or highlighting like a card when it has focus.
private struct PlayerBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct PlayerTrackButtons: View {
    let model: PlayerModel

    var body: some View {
        HStack(spacing: 24) {
            if let engine = model.engine {
                if engine.audioTracks.count > 1 {
                    Menu {
                        ForEach(engine.audioTracks) { track in
                            trackButton(track.title, selected: engine.selectedAudioTrackID == track.id) {
                                await model.selectAudioTrack(id: track.id)
                            }
                        }
                    } label: {
                        Label("Audio", systemImage: "speaker.wave.2")
                    }
                    .accessibilityIdentifier("audioTracks")
                }
                if !engine.subtitleTracks.isEmpty {
                    Menu {
                        trackButton("Off", selected: engine.selectedSubtitleTrackID == nil) {
                            await model.selectSubtitleTrack(id: nil)
                        }
                        ForEach(engine.subtitleTracks) { track in
                            trackButton(track.title, selected: engine.selectedSubtitleTrackID == track.id) {
                                await model.selectSubtitleTrack(id: track.id)
                            }
                        }
                    } label: {
                        Label("Subtitles", systemImage: "captions.bubble")
                    }
                    .accessibilityIdentifier("subtitleTracks")
                }
            }
        }
        .buttonStyle(.glass)
    }

    private func trackButton(_ title: String, selected: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

private struct PlayerUpNextCard: View {
    let item: MediaItem
    let secondsLeft: Int
    let onPlay: () -> Void
    let onCancel: () -> Void

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
