import SwiftUI

enum MediaCardStyle {
    case poster
    /// Home keeps the item's details above the row, so its posters leave them room.
    case posterCompact
    case landscape
    /// Four of these with 48pt gaps fill the 1760pt between the safe area margins exactly.
    case landscapeGrid

    var size: CGSize {
        switch self {
        case .poster: CGSize(width: 260, height: 390)
        case .posterCompact: CGSize(width: 220, height: 330)
        case .landscape: CGSize(width: 440, height: 248)
        case .landscapeGrid: CGSize(width: 404, height: 227)
        }
    }
}

/// A focusable piece of artwork with its title beneath, used for posters and landscape cards.
/// `onPlay` responds to the remote's Play/Pause button, and `menu` to a long press of Select.
struct MediaCard<Menu: View>: View {
    let style: MediaCardStyle
    let title: String
    var subtitle: String?
    let imageURL: URL?
    /// Watched fraction from 0 to 1. A nil value shows no progress bar.
    var progress: Double?
    /// Shows a check mark for an item that has been watched to the end.
    var isWatched = false
    var onPlay: (() -> Void)?
    /// Tells the screen when this card gains or loses focus.
    var onFocusChange: ((Bool) -> Void)?
    let action: () -> Void
    @ViewBuilder var menu: () -> Menu

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Button(action: action) {
                CachedImage(url: imageURL, placeholderSymbol: style == .poster || style == .posterCompact ? "film" : "photo")
                    .frame(width: style.size.width, height: style.size.height)
                    .overlay(alignment: .bottom) {
                        if let progress {
                            ProgressBar(fraction: progress)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isWatched {
                            WatchedBadge()
                                .padding(12)
                        }
                    }
                    .clipped()
            }
            .buttonStyle(.card)
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in onFocusChange?(focused) }
            .contextMenu(menuItems: menu)
            .onPlayPauseCommand(perform: onPlay)
            .accessibilityLabel(title)
            .accessibilityValue([subtitle, isWatched ? "Watched" : nil].compactMap(\.self).joined(separator: ", "))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(isFocused ? .primary : .secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .frame(width: style.size.width, alignment: .leading)
        }
    }
}

extension MediaCard where Menu == EmptyView {
    init(
        style: MediaCardStyle,
        title: String,
        subtitle: String? = nil,
        imageURL: URL?,
        progress: Double? = nil,
        isWatched: Bool = false,
        onPlay: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            style: style,
            title: title,
            subtitle: subtitle,
            imageURL: imageURL,
            progress: progress,
            isWatched: isWatched,
            onPlay: onPlay,
            action: action,
            menu: { EmptyView() }
        )
    }
}

/// A check mark on a dark disc, so it stays readable on bright artwork from across a room.
struct WatchedBadge: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .glassEffect(.regular.tint(.black.opacity(0.5)), in: .circle)
    }
}

struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(.black.opacity(0.5))
                Rectangle()
                    .fill(.white)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 8)
    }
}
