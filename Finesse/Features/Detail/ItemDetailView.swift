import SwiftUI

/// The route for `AppRoute.detail`: the movie, show, season or episode page, in that order of
/// hero, Play and actions, then the rows that belong to the kind of item.
struct ItemDetailView: View {
    @Environment(\.jellyfinClient) private var client
    let item: MediaItem

    var body: some View {
        DetailContent(model: DetailModel(item: item, client: client))
    }
}

private struct DetailContent: View {
    private enum Focus: Hashable {
        /// Holds focus while the page loads. Without it, focus stays on the screen underneath, and
        /// the remote acts on that hidden screen until something here can take it.
        case loading
        case play
        case watched
    }

    @Environment(AppModel.self) private var app
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.jellyfinClient) private var client
    @State var model: DetailModel
    @FocusState private var focus: Focus?
    /// How far the page has scrolled, so the backdrop can dim behind the text moving over it.
    @State private var scrollOffset: CGFloat = 0

    private var item: MediaItem { model.item }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            DetailBackdrop(url: client.heroURL(for: item), dimming: min(max(scrollOffset, 0) / 400, 1))
            switch model.phase {
            case .loading:
                LoadingStateView()
                    .focusable()
                    .focused($focus, equals: .loading)
                    .accessibilityIdentifier("detailLoading")
            case .failed(let message):
                ErrorStateView(message: message) {
                    Task { await model.load() }
                }
            case .loaded:
                page
            }
        }
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .tabBar)
        .task { await model.load() }
        // Watched state and progress, quietly, while the page is showing.
        .refreshesOnServerChanges(isPaused: navigator.activePlayback != nil) { await model.load() }
        .onChange(of: model.phase == .loaded) { _, loaded in
            // The loading view had focus, so hand it to the page's first action as it replaces it.
            guard loaded, focus == .loading || focus == nil else { return }
            // The buttons arrive in this same update, so wait a turn for them to be focusable.
            Task { @MainActor in
                focus = model.playTarget == nil ? .watched : .play
            }
        }
        .onChange(of: navigator.activePlayback == nil) { _, finished in
            if finished { Task { await model.load() } }
        }
        .onChange(of: model.sessionExpired) { _, expired in
            if expired { app.sessionExpired() }
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })
        ) {
            Button("OK") { model.actionError = nil }
        } message: {
            Text(model.actionError ?? "")
        }
    }

    private var page: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 72) {
                header
                    .padding(.top, 280)
                    .focusSection()
                rows
            }
        }
        .scrollClipDisabled()
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            scrollOffset = offset
        }
        .defaultFocus($focus, .play)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let parent = parentTitle {
                Text(parent)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text(item.name)
                .font(.system(size: 76, weight: .bold))
                .lineLimit(2)
            let metadata = item.detailMetadata
            if !metadata.isEmpty {
                Text(metadata.joined(separator: "  \u{00B7}  "))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
            }
            if !item.genres.isEmpty {
                Text(item.genres.prefix(4).joined(separator: ", "))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
            }
            if let tagline = item.tagline {
                Text(tagline)
                    .font(.headline)
            }
            if let overview = item.overview {
                Text(overview)
                    .font(.callout)
                    .lineLimit(4)
                    .frame(maxWidth: 1200, alignment: .leading)
            }
            actions
                .padding(.top, 16)
        }
    }

    private var parentTitle: String? {
        switch item.kind {
        case .season, .episode: item.seriesName
        default: nil
        }
    }

    private var actions: some View {
        HStack(spacing: 24) {
            if let target = model.playTarget {
                Button {
                    navigator.play(target, resumeFrom: target.resumePosition)
                } label: {
                    Label(model.playTitle, systemImage: "play.fill")
                }
                .buttonStyle(.glassProminent)
                .focused($focus, equals: .play)
                .accessibilityIdentifier("detailPlay")

                if target.resumePosition != nil {
                    Button {
                        navigator.play(target, resumeFrom: nil)
                    } label: {
                        Label("Start Over", systemImage: "backward.end.fill")
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("detailStartOver")
                }
            }
            Button {
                Task { await model.toggleWatched() }
            } label: {
                Label(
                    item.userState.isPlayed ? "Mark Unwatched" : "Mark Watched",
                    systemImage: item.userState.isPlayed ? "checkmark.circle.fill" : "checkmark.circle"
                )
            }
            .buttonStyle(.glass)
            .focused($focus, equals: .watched)
            .accessibilityIdentifier("detailWatched")

            Button {
                Task { await model.toggleFavorite() }
            } label: {
                Label(
                    item.userState.isFavorite ? "Favourited" : "Favourite",
                    systemImage: item.userState.isFavorite ? "heart.fill" : "heart"
                )
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("detailFavourite")

            if item.kind == .season || item.kind == .episode, let seriesID = item.seriesID {
                Button {
                    navigator.show(.detail(MediaItem(id: seriesID, name: item.seriesName ?? "", kind: .series)))
                } label: {
                    Label("Go to Show", systemImage: "tv")
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("detailGoToShow")
            }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var rows: some View {
        switch item.kind {
        case .series:
            posterRow("Seasons", items: model.seasons)
            castRow
            posterRow("More Like This", items: model.similar)
        case .season:
            episodeGrid
            castRow
        case .episode:
            episodeRow("More in This Season", items: model.otherEpisodes)
            castRow
        default:
            castRow
            posterRow("More Like This", items: model.similar)
        }
    }

    @ViewBuilder
    private func posterRow(_ title: String, items: [MediaItem]) -> some View {
        if !items.isEmpty {
            HubRow(title: title, items: items) { item in
                MediaCard(
                    style: .poster,
                    title: item.name,
                    subtitle: item.cardSubtitle,
                    imageURL: client.posterURL(for: item),
                    progress: item.watchedFraction,
                    isWatched: item.isWatched,
                    unwatchedCount: item.unwatchedCount,
                    onPlay: item.isPlayable ? { navigator.play(item, resumeFrom: item.resumePosition) } : nil,
                    action: { navigator.show(.detail(item)) }
                )
            }
        }
    }

    @ViewBuilder
    private func episodeRow(_ title: String, items: [MediaItem]) -> some View {
        if !items.isEmpty {
            HubRow(title: title, items: items) { item in
                episodeCard(item)
            }
        }
    }

    @ViewBuilder
    private var episodeGrid: some View {
        if !model.episodes.isEmpty {
            VStack(alignment: .leading, spacing: 24) {
                Text("Episodes")
                    .font(.title3)
                    .fontWeight(.semibold)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(MediaCardStyle.landscapeGrid.size.width), spacing: 48), count: 4),
                    alignment: .leading,
                    spacing: 48
                ) {
                    ForEach(model.episodes) { item in
                        episodeCard(item, style: .landscapeGrid)
                    }
                }
            }
            .focusSection()
        }
    }

    private func episodeCard(_ item: MediaItem, style: MediaCardStyle = .landscape) -> some View {
        MediaCard(
            style: style,
            title: item.indexNumber.map { "\($0). \(item.name)" } ?? item.name,
            subtitle: item.runTime.flatMap(MediaItem.runTimeText),
            imageURL: client.landscapeURL(for: item),
            progress: item.watchedFraction,
            isWatched: item.isWatched,
            onPlay: { navigator.play(item, resumeFrom: item.resumePosition) },
            action: { navigator.show(.detail(item)) }
        )
    }

    @ViewBuilder
    private var castRow: some View {
        if !item.people.isEmpty {
            HubRow(title: "Cast & Crew", items: item.people) { person in
                PersonCard(
                    person: person,
                    imageURL: client.imageURL(
                        itemID: person.id,
                        kind: .primary,
                        tag: person.primaryImageTag,
                        index: nil,
                        maxWidth: 300
                    )
                )
            }
        }
    }
}

private struct DetailBackdrop: View {
    let url: URL?
    /// From 0 at the top of the page to 1 once the header has moved up over the bright part.
    let dimming: Double

    var body: some View {
        GeometryReader { geometry in
            CachedImage(url: url)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.25), location: 0),
                            .init(color: .black.opacity(0.75), location: 0.45),
                            .init(color: .black.opacity(0.95), location: 0.8),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay {
                    Color.black.opacity(0.7 * dimming)
                }
        }
        .ignoresSafeArea()
    }
}

/// Focusable so the row can be scrolled with the remote. There's no person page in v1, so it has no action.
private struct PersonCard: View {
    let person: Person
    let imageURL: URL?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CachedImage(url: imageURL, placeholderSymbol: "person.fill")
                .frame(width: 200, height: 300)
                .clipShape(.rect(cornerRadius: 12))
                .scaleEffect(isFocused ? 1.08 : 1)
                .shadow(radius: isFocused ? 16 : 0)
                .animation(.easeOut(duration: 0.15), value: isFocused)
            VStack(alignment: .leading, spacing: 4) {
                Text(person.name)
                    .font(.callout)
                    .foregroundStyle(isFocused ? .primary : .secondary)
                if let role = person.role ?? person.type {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .frame(width: 200, alignment: .leading)
        }
        .focusable()
        .focused($isFocused)
        .accessibilityElement(children: .combine)
    }
}

extension JellyfinClient {
    /// The full-screen image behind a Detail page: the item's own backdrop, else its parent's, else
    /// the best 16:9 image it has. An episode leads with its own still.
    func heroURL(for item: MediaItem) -> URL? {
        let maxWidth = 1920
        if item.kind == .episode, item.images.primaryTag != nil {
            return landscapeURL(for: item, maxWidth: maxWidth)
        }
        if let tag = item.images.backdropTags.first {
            return imageURL(itemID: item.id, kind: .backdrop, tag: tag, index: 0, maxWidth: maxWidth)
        }
        if let parent = item.images.parentBackdropItemID, let tag = item.images.parentBackdropTags.first {
            return imageURL(itemID: parent, kind: .backdrop, tag: tag, index: 0, maxWidth: maxWidth)
        }
        return landscapeURL(for: item, maxWidth: maxWidth)
    }
}
