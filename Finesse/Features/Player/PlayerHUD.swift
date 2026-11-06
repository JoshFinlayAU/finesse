import SwiftUI

enum PlayerFocus: Hashable {
    case surface
    case skip
    case main
    case panelButton(PlayerPanel)
    case panelRow(String)
}

extension PlayerPanel {
    var title: String {
        switch self {
        case .audio: "Audio"
        case .subtitles: "Subtitles"
        case .playback: "Picture and Speed"
        case .chapters: "Chapters"
        case .episodes: "Episodes"
        case .quality: "Quality"
        case .info: "Info"
        }
    }

    var symbol: String {
        switch self {
        case .audio: "speaker.wave.2"
        case .subtitles: "captions.bubble"
        case .playback: "dial.medium"
        case .chapters: "list.bullet.rectangle"
        case .episodes: "rectangle.stack"
        case .quality: "antenna.radiowaves.left.and.right"
        case .info: "info.circle"
        }
    }
}

/// Dark enough behind white text to stay readable over a bright frame, and still glass.
let hudGlass = Glass.regular.tint(.black.opacity(0.45))
let hudCorner: CGFloat = 44

/// The controls a swipe up brings in, at the bottom edge of the safe area.
struct PlayerHUDBar: View {
    let model: PlayerModel
    let focus: FocusState<PlayerFocus?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PlayerTitleRow(item: model.item, position: model.displayPosition, duration: model.duration, rate: model.options.rate)
            PlayerTimeline(position: model.displayPosition, duration: model.duration, chapters: model.chapters)
            HStack(spacing: 12) {
                if let previous = model.previousEpisode {
                    HUDButton(symbol: "backward.end.fill", title: "Previous Episode", id: "hudPrevious") {
                        Task { await model.playEpisode(previous) }
                    }
                }
                HUDButton(symbol: "arrow.left.and.right", title: "Seek", id: "hudPlayPause") {
                    Task { await model.send(.click) }
                }
                .focused(focus, equals: .main)
                if let next = model.nextEpisode {
                    HUDButton(symbol: "forward.end.fill", title: "Next Episode", id: "hudNext") {
                        Task { await model.playEpisode(next) }
                    }
                }
                Spacer(minLength: 24)
                ForEach(model.panels, id: \.self) { panel in
                    HUDButton(symbol: panel.symbol, title: panel.title, id: "hud-\(panel.rawValue)", isOn: model.controls.panel == panel) {
                        Task { await model.send(.openPanel(panel)) }
                    }
                    .focused(focus, equals: .panelButton(panel))
                }
            }
            .focusSection()
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .glassEffect(hudGlass, in: .rect(cornerRadius: hudCorner))
    }
}

/// What a click brings up: only the timeline, because left and right now move it.
struct PlayerScrubBar: View {
    let model: PlayerModel
    let scrub: PlayerControls.Scrub

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(PlayerTime.format(scrub.target))
                    .font(.title2.weight(.semibold).monospacedDigit())
                if scrub.target != scrub.origin {
                    Text(difference)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let name = model.chapter(at: scrub.target)?.name {
                    Text(name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 24)
                Text(model.duration.map(PlayerTime.format) ?? "")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            PlayerTimeline(position: scrub.target, duration: model.duration, chapters: model.chapters, isScrubbing: true)
            Text("Click to play from here. Back to cancel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .glassEffect(hudGlass, in: .rect(cornerRadius: hudCorner))
        .accessibilityIdentifier("scrubBar")
    }

    private var difference: String {
        let seconds = scrub.target.seconds - scrub.origin.seconds
        return (seconds < 0 ? "-" : "+") + PlayerTime.format(Ticks(seconds: abs(seconds)))
    }
}

/// So a pause from the remote's Play/Pause button doesn't look like a frozen picture.
struct PlayerPausedPill: View {
    let position: Ticks

    var body: some View {
        Label(PlayerTime.format(position), systemImage: "pause.fill")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .glassEffect(hudGlass, in: .capsule)
            .accessibilityIdentifier("pausedPill")
    }
}

private struct PlayerTitleRow: View {
    let item: MediaItem
    let position: Ticks
    let duration: Ticks?
    let rate: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(item.cardTitle)
                .font(.headline)
                .lineLimit(1)
            if let subtitle = item.cardSubtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 24)
            Text(PlayerTime.format(position))
                .font(.callout.weight(.medium).monospacedDigit())
            if let duration {
                Text("/ \(PlayerTime.format(duration))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("Ends at \(endTime(duration).formatted(date: .omitted, time: .shortened))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func endTime(_ duration: Ticks) -> Date {
        .now.addingTimeInterval(max(duration.seconds - position.seconds, 0) / max(rate, 0.1))
    }
}

/// A thin line that thickens while scrubbing, with a mark at each chapter.
private struct PlayerTimeline: View {
    let position: Ticks
    let duration: Ticks?
    let chapters: [ItemChapter]
    var isScrubbing = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white).frame(width: max(width * fraction(position), height))
                ForEach(chapters.dropFirst()) { chapter in
                    Rectangle()
                        .fill(.black.opacity(0.5))
                        .frame(width: 3)
                        .offset(x: width * fraction(chapter.start))
                }
                if isScrubbing {
                    Circle()
                        .fill(.white)
                        .frame(width: height * 2.4, height: height * 2.4)
                        .shadow(radius: 6)
                        .offset(x: width * fraction(position) - height * 1.2)
                }
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
        }
        .frame(height: height * 2.4)
        .animation(.easeOut(duration: 0.2), value: position)
    }

    private var height: CGFloat { isScrubbing ? 12 : 8 }

    private func fraction(_ ticks: Ticks) -> Double {
        guard let total = duration?.seconds, total > 0 else {
            return 0
        }
        return min(max(ticks.seconds / total, 0), 1)
    }
}

/// An icon that names itself when focused, which keeps the bar quiet.
struct HUDButton: View {
    let symbol: String
    let title: String
    let id: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .accessibilityLabel(title)
        }
        .buttonStyle(HUDButtonStyle(title: title, isOn: isOn))
        .accessibilityIdentifier(id)
    }
}

private struct HUDButtonStyle: ButtonStyle {
    let title: String
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        Body(label: configuration.label, title: title, isOn: isOn, isPressed: configuration.isPressed)
    }

    private struct Body<Label: View>: View {
        let label: Label
        let title: String
        let isOn: Bool
        let isPressed: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            HStack(spacing: 12) {
                label
                if isFocused {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .font(.title3)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .background {
                Capsule().fill(isFocused ? Color.white : isOn ? Color.white.opacity(0.22) : Color.clear)
            }
            .scaleEffect(isPressed ? 0.95 : 1)
            .animation(.smooth(duration: 0.18), value: isFocused)
        }
    }
}

/// A row in a panel: quiet until focused.
struct PanelRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Body(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct Body<Label: View>: View {
        let label: Label
        let isPressed: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            label
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .background {
                    RoundedRectangle(cornerRadius: 20).fill(isFocused ? Color.white : Color.clear)
                }
                .scaleEffect(isPressed ? 0.98 : 1)
                .animation(.smooth(duration: 0.15), value: isFocused)
        }
    }
}
