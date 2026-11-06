import SwiftUI
import UIKit

/// Full-screen art that holds the old image until the new one is ready, then fades across. The
/// scrims keep white text readable on bright art and the tab bar readable at the top.
struct HomeBackdrop: View {
    let url: URL?
    let isDimmed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: ShownArt?

    private struct ShownArt: Equatable {
        let url: URL
        let image: UIImage
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let shown {
                    DriftingArt(image: shown.image, size: geometry.size, drifts: !reduceMotion)
                        .id(shown.url)
                        .transition(.opacity)
                }
                scrims
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else {
                shown = nil
                return
            }
            guard let image = try? await ImagePipeline.shared.image(for: url), !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.7)) {
                shown = ShownArt(url: url, image: image)
            }
        }
    }

    private var scrims: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.88), location: 0),
                    .init(color: .black.opacity(0.62), location: 0.4),
                    .init(color: .clear, location: 0.8),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.45),
                    .init(color: .black.opacity(0.92), location: 0.82),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Color.black.opacity(isDimmed ? 0.25 : 0)
                .animation(.easeInOut(duration: 0.35), value: isDimmed)
        }
    }
}

/// Moves very slowly, so a still image doesn't feel frozen on a large screen.
private struct DriftingArt: View {
    let image: UIImage
    let size: CGSize
    let drifts: Bool

    @State private var isDrifted = false

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .scaleEffect(isDrifted ? 1.05 : 1, anchor: .topTrailing)
            .onAppear {
                guard drifts else { return }
                withAnimation(.linear(duration: 30)) {
                    isDrifted = true
                }
            }
    }
}

/// The title and what's known about it. It stays in place while the rows move beneath it.
struct HomeHeroDetails: View {
    let content: HomeHeroContent?
    let isCompact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let content {
                details(content)
                    .id(content.item.id)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: 1100, alignment: .topLeading)
        .padding(.top, isCompact ? 70 : 200)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: content)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: isCompact)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private func details(_ content: HomeHeroContent) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeTitleLogo(title: content.title, url: content.logoURL, isCompact: isCompact)
            if let subtitle = content.subtitle {
                Text(subtitle)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("heroSubtitle")
            }
            if !content.metadata.isEmpty {
                Text(content.metadata.joined(separator: "  \u{00B7}  "))
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .accessibilityIdentifier("heroMetadata")
            }
            if !content.genres.isEmpty {
                Text(content.genres.joined(separator: ", "))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            if let overview = content.overview {
                Text(overview)
                    .font(.callout)
                    .lineLimit(isCompact ? 2 : 3)
                    .padding(.top, 4)
                    .accessibilityIdentifier("heroOverview")
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
    }
}

/// The title's logo where the server has one, and the title as text until it loads or if it can't.
private struct HomeTitleLogo: View {
    let title: String
    let url: URL?
    let isCompact: Bool

    @State private var logo: UIImage?

    private var height: CGFloat { isCompact ? 110 : 170 }

    var body: some View {
        Group {
            if let logo {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 640, maxHeight: height, alignment: .bottomLeading)
                    .frame(height: height, alignment: .bottomLeading)
            } else {
                Text(title)
                    .font(.system(size: isCompact ? 56 : 76, weight: .bold))
                    .lineLimit(isCompact ? 1 : 2)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityIdentifier("heroTitle")
        .task(id: url) {
            guard let url else {
                logo = nil
                return
            }
            logo = ImagePipeline.shared.cachedImage(for: url)
            guard logo == nil else { return }
            logo = try? await ImagePipeline.shared.image(for: url)
        }
    }
}
