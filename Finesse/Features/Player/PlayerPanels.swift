import SwiftUI

/// One group of options, in glass, above the bar. Everything it changes goes through the model.
struct PlayerPanelView: View {
    let panel: PlayerPanel
    let model: PlayerModel
    let focus: FocusState<PlayerFocus?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(panel.title)
                .font(.headline)
                .padding(.horizontal, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    content
                }
                .padding(.vertical, 8)
            }
            .clipShape(.rect(cornerRadius: 20))
        }
        .padding(28)
        .frame(width: panel.isWide ? 1100 : 760)
        .frame(maxHeight: 620, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(hudGlass, in: .rect(cornerRadius: hudCorner))
        .focusSection()
        .accessibilityIdentifier("panel-\(panel.rawValue)")
    }

    @ViewBuilder private var content: some View {
        switch panel {
        case .audio: audio
        case .subtitles: subtitles
        case .playback: playback
        case .chapters: chapters
        case .episodes: episodes
        case .quality: quality
        case .info: info
        }
    }

    // MARK: Groups

    @ViewBuilder private var audio: some View {
        if let engine = model.engine {
            ForEach(engine.audioTracks) { track in
                let selected = engine.selectedAudioTrackID == track.id
                row(track.title, selected: selected, id: "audio-\(track.id)") {
                    await model.selectAudioTrack(id: track.id)
                }
            }
        }
        sectionGap
        stepper(
            "Audio Delay",
            value: Self.delayText(model.options.audioDelay),
            option: .audioDelay,
            id: "audioDelay"
        ) { await model.adjustAudioDelay(by: $0) }
    }

    @ViewBuilder private var subtitles: some View {
        if let engine = model.engine {
            let off = engine.selectedSubtitleTrackID == nil
            row("Off", selected: off, id: "subtitle-off") {
                await model.selectSubtitleTrack(id: nil)
            }
            ForEach(engine.subtitleTracks) { track in
                let selected = engine.selectedSubtitleTrackID == track.id
                row(track.title, selected: selected, id: "subtitle-\(track.id)") {
                    await model.selectSubtitleTrack(id: track.id)
                }
            }
        }
        sectionGap
        stepper(
            "Subtitle Offset",
            value: Self.delayText(model.options.subtitleDelay),
            option: .subtitleDelay,
            id: "subtitleDelay"
        ) { await model.adjustSubtitleDelay(by: $0) }
        stepper(
            "Size",
            value: "\(Int((model.options.subtitleScale * 100).rounded()))%",
            option: .subtitleStyle,
            id: "subtitleSize"
        ) { await model.adjustSubtitleScale(by: $0) }
        stepper(
            "Position",
            value: model.options.subtitleRaise == 0 ? "Normal" : "Up \(model.options.subtitleRaise)%",
            option: .subtitleStyle,
            id: "subtitlePosition"
        ) { await model.adjustSubtitleRaise(by: $0) }
    }

    @ViewBuilder private var playback: some View {
        sectionTitle("Speed")
        ForEach(PlaybackOptions.rates, id: \.self) { rate in
            let selected = model.options.rate == rate
            row(rate == 1 ? "Normal" : String(format: "%gx", rate), selected: selected, id: "rate-\(rate)") {
                await model.setRate(rate)
            }
        }
        sectionGap
        sectionTitle("Picture")
        ForEach(PictureMode.allCases, id: \.self) { mode in
            row(mode.title, selected: model.options.pictureMode == mode, id: "picture-\(mode.rawValue)") {
                await model.setPictureMode(mode)
            }
        }
    }

    @ViewBuilder private var chapters: some View {
        let current = model.chapter(at: model.displayPosition)?.id
        ForEach(model.chapters) { chapter in
            let selected = chapter.id == current
            Button {
                Task { await model.selectChapter(chapter) }
            } label: {
                HStack(spacing: 20) {
                    if let url = model.chapterImageURL(chapter) {
                        CachedImage(url: url)
                            .frame(width: 192, height: 108)
                            .clipShape(.rect(cornerRadius: 12))
                    }
                    Text(chapter.name ?? "Chapter \(chapter.index + 1)")
                        .lineLimit(1)
                    Spacer(minLength: 16)
                    Text(PlayerTime.format(chapter.start))
                        .font(.callout.monospacedDigit())
                    if selected {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .buttonStyle(PanelRowStyle())
            .focused(focus, equals: .panelRow("chapter-\(chapter.index)"))
            .accessibilityIdentifier("chapter-\(chapter.index)")
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    @ViewBuilder private var episodes: some View {
        ForEach(model.episodes) { episode in
            let selected = episode.id == model.item.id
            Button {
                Task { await model.playEpisode(episode) }
            } label: {
                HStack(spacing: 20) {
                    CachedImage(url: model.thumbnailURL(episode), placeholderSymbol: "tv")
                        .frame(width: 192, height: 108)
                        .clipShape(.rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(episode.cardTitle)
                            .lineLimit(1)
                        if let subtitle = episode.cardSubtitle {
                            Text(subtitle)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 16)
                    if selected {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .buttonStyle(PanelRowStyle())
            .focused(focus, equals: .panelRow("episode-\(episode.id)"))
            .accessibilityIdentifier("episode-\(episode.id)")
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    @ViewBuilder private var quality: some View {
        ForEach(PlayerModel.bitrateChoices, id: \.self) { bitrate in
            let selected = model.preferences.maxBitrate == bitrate
            row(
                bitrate.map(PlayerInfo.bitrate) ?? "Original",
                selected: selected,
                id: "bitrate-\(bitrate ?? 0)"
            ) {
                await model.setMaxBitrate(bitrate)
            }
        }
        if let text = model.qualityNote {
            note(text)
        }
        if !model.versions.isEmpty {
            sectionGap
            sectionTitle("Version")
            ForEach(model.versions) { version in
                row(
                    version.name ?? version.id,
                    selected: model.session?.route?.mediaSourceID == version.id,
                    id: "version-\(version.id)"
                ) {
                    await model.selectVersion(id: version.id)
                }
            }
        }
    }

    @ViewBuilder private var info: some View {
        // Read-only, but something has to hold focus for Back and for scrolling.
        Button {} label: {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.infoRows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 20) {
                        Text(row.title)
                            .font(.callout)
                            .frame(width: 220, alignment: .leading)
                        Text(row.value)
                            .font(.callout.weight(.medium))
                            .lineLimit(2)
                    }
                }
            }
        }
        .buttonStyle(PanelInfoStyle())
        .focused(focus, equals: .panelRow("infoRows"))
        .accessibilityIdentifier("infoRows")
    }

    // MARK: Pieces

    private var sectionGap: some View {
        Color.clear.frame(height: 14)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
    }

    private func row(
        _ title: String,
        selected: Bool,
        id: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 16)
                if selected {
                    Image(systemName: "checkmark")
                }
            }
        }
        .buttonStyle(PanelRowStyle())
        .focused(focus, equals: .panelRow(id))
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Disabled with its reason when the engine can't do it, or says so when it would move engines.
    @ViewBuilder private func stepper(
        _ title: String,
        value: String,
        option: PlaybackOption,
        id: String,
        change: @escaping (Int) async -> Void
    ) -> some View {
        let availability = model.availability(of: option)
        let isDisabled = if case .unavailable = availability { true } else { false }
        HStack(spacing: 8) {
            Text(title)
                .padding(.leading, 22)
            Spacer(minLength: 16)
            stepButton("minus", id: "\(id)-minus") { await change(-1) }
            Text(value)
                .font(.callout.monospacedDigit())
                .frame(minWidth: 130)
                .accessibilityIdentifier("\(id)-value")
                .accessibilityLabel(value)
            stepButton("plus", id: "\(id)-plus") { await change(1) }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .focusSection()
        switch availability {
        case .available:
            EmptyView()
        case .movesEngine:
            note("Changing this switches to the other player, at the same position.")
                .accessibilityIdentifier("\(id)-note")
        case .unavailable(let reason):
            note(reason)
                .accessibilityIdentifier("\(id)-note")
        }
    }

    private func stepButton(_ symbol: String, id: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .frame(width: 44)
        }
        .buttonStyle(PanelStepStyle())
        .accessibilityIdentifier(id)
    }
}

private extension PlayerPanel {
    var isWide: Bool {
        self == .episodes || self == .chapters || self == .info
    }
}

extension PictureMode {
    var title: String {
        switch self {
        case .fit: "Fit"
        case .fill: "Fill"
        case .stretch: "Stretch"
        }
    }
}

extension PlayerPanelView {
    static func delayText(_ seconds: TimeInterval) -> String {
        seconds == 0 ? "None" : String(format: "%+.1f s", seconds)
    }
}

private struct PanelStepStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Body(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct Body<Label: View>: View {
        let label: Label
        let isPressed: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            label
                .padding(12)
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .background {
                    Circle().fill(isFocused ? Color.white : Color.white.opacity(0.14))
                }
                .scaleEffect(isPressed ? 0.92 : 1)
                .animation(.smooth(duration: 0.15), value: isFocused)
        }
    }
}

/// Nothing happens on a read-only panel, so focus shouldn't look like a choice.
private struct PanelInfoStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 22)
    }
}
