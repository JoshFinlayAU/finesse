import SwiftUI

/// The Search tab, using the system tvOS search field and keyboard.
struct SearchRootView: View {
    @Environment(\.jellyfinClient) private var client

    var body: some View {
        SearchContent(model: SearchModel(client: client))
    }
}

private struct SearchContent: View {
    @Environment(AppModel.self) private var app
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.jellyfinClient) private var client
    @State var model: SearchModel
    @State private var text = ""

    var body: some View {
        results
            .searchable(text: $text, prompt: "Movies, shows and episodes")
            .task(id: text) { await model.search(text) }
            .onChange(of: model.sessionExpired) { _, expired in
                if expired { app.sessionExpired() }
            }
    }

    @ViewBuilder
    private var results: some View {
        switch model.state {
        case .idle:
            EmptyStateView(title: "Search Your Library", systemImage: "magnifyingglass")
        case .loading:
            LoadingStateView()
        case .failed(let message):
            ErrorStateView(message: message) {
                Task { await model.search(text) }
            }
        case .loaded(let groups) where groups.isEmpty:
            EmptyStateView(title: "No Results", message: "Nothing matches \u{201C}\(text)\u{201D}.", systemImage: "magnifyingglass")
        case .loaded(let groups):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 64) {
                    ForEach(groups) { group in
                        HubRow(title: group.title, items: group.items) { item in
                            card(for: item)
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func card(for item: MediaItem) -> some View {
        let isEpisode = item.kind == .episode
        return MediaCard(
            style: isEpisode ? .landscape : .poster,
            title: item.cardTitle,
            subtitle: item.cardSubtitle,
            imageURL: isEpisode ? client.landscapeURL(for: item) : client.posterURL(for: item),
            progress: item.watchedFraction,
            isWatched: item.isWatched,
            unwatchedCount: item.unwatchedCount,
            onPlay: item.isPlayable ? { navigator.play(item, resumeFrom: item.resumePosition) } : nil,
            action: { navigator.show(.detail(item)) }
        )
    }
}
