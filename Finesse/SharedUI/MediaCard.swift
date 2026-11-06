import SwiftUI

enum MediaCardStyle {
    case poster
    case landscape

    var size: CGSize {
        switch self {
        case .poster: CGSize(width: 260, height: 390)
        case .landscape: CGSize(width: 440, height: 248)
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
    var onPlay: (() -> Void)?
    let action: () -> Void
    @ViewBuilder var menu: () -> Menu

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Button(action: action) {
                CachedImage(url: imageURL, placeholderSymbol: style == .poster ? "film" : "photo")
                    .frame(width: style.size.width, height: style.size.height)
                    .overlay(alignment: .bottom) {
                        if let progress {
                            ProgressBar(fraction: progress)
                        }
                    }
                    .clipped()
            }
            .buttonStyle(.card)
            .focused($isFocused)
            .contextMenu(menuItems: menu)
            .onPlayPauseCommand(perform: onPlay)
            .accessibilityLabel(title)
            .accessibilityValue(subtitle ?? "")

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
        onPlay: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            style: style,
            title: title,
            subtitle: subtitle,
            imageURL: imageURL,
            progress: progress,
            onPlay: onPlay,
            action: action,
            menu: { EmptyView() }
        )
    }
}

struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(.black.opacity(0.5))
                Rectangle()
                    .fill(.tint)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 8)
    }
}
