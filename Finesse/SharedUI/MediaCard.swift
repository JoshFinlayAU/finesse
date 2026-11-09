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
    /// Unwatched episodes on a series or season card. Nil or 0 shows no count.
    var unwatchedCount: Int?
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
                        } else if let unwatchedCount, unwatchedCount > 0 {
                            UnwatchedCountBadge(count: unwatchedCount)
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
            .accessibilityValue(accessibilityValue)

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

    private var accessibilityValue: String {
        let count = isWatched ? nil : unwatchedCount.flatMap { $0 > 0 ? UnwatchedCountBadge.spokenText(for: $0) : nil }
        return [subtitle, isWatched ? "Watched" : nil, count].compactMap(\.self).joined(separator: ", ")
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
        unwatchedCount: Int? = nil,
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
            unwatchedCount: unwatchedCount,
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

/// How many episodes are left, in the same dark glass as the check mark, so it reads from across a
/// room on any artwork. It sits in the corner, clear of the title beneath the card.
struct UnwatchedCountBadge: View {
    let count: Int

    /// Counts over 99 show as 99+, so the badge never grows past the corner.
    static func text(for count: Int) -> String {
        count > 99 ? "99+" : String(count)
    }

    static func spokenText(for count: Int) -> String {
        count == 1 ? "1 unwatched episode" : "\(count) unwatched episodes"
    }

    var body: some View {
        Text(Self.text(for: count))
            .font(.system(size: 26, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .frame(minWidth: 48, minHeight: 48)
            .glassEffect(.regular.tint(.black.opacity(0.5)), in: .capsule)
            // The card's own value says the count in words.
            .accessibilityHidden(true)
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
