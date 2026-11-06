import SwiftUI

struct HomeView: View {
    @Environment(\.jellyfinClient) private var client

    var body: some View {
        HomeContent(model: HomeModel(client: client))
    }
}

private struct HomeContent: View {
    @Environment(AppModel.self) private var app
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.jellyfinClient) private var client
    @State var model: HomeModel

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                LoadingStateView()
            case .failed(let message):
                ErrorStateView(message: message) {
                    Task { await model.load() }
                }
            case .loaded(let hubs) where hubs.isEmpty:
                EmptyStateView(
                    title: "Nothing to Show Yet",
                    message: "Your recently added and in-progress items will appear here.",
                    systemImage: "house"
                )
            case .loaded(let hubs):
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 64) {
                        ForEach(hubs) { hub in
                            HubRow(title: hub.title, items: hub.items) { item in
                                card(for: item, in: hub.kind)
                            }
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
        // Runs each time Home reappears, so progress is current after Detail.
        .task { await model.load() }
        // The player covers Home without it disappearing, so `.task` doesn't rerun when it closes.
        // The player reports stop before clearing this, so the reload sees the final position.
        .onChange(of: navigator.activePlayback == nil) { _, playerClosed in
            if playerClosed {
                Task { await model.load() }
            }
        }
        .onChange(of: model.sessionExpired) { _, expired in
            if expired { app.sessionExpired() }
        }
    }

    @ViewBuilder
    private func card(for item: MediaItem, in kind: HomeHub.Kind) -> some View {
        let isPoster = kind == .recentlyAdded
        MediaCard(
            style: isPoster ? .poster : .landscape,
            title: item.cardTitle,
            subtitle: item.cardSubtitle,
            imageURL: isPoster ? client.posterURL(for: item) : client.landscapeURL(for: item),
            progress: item.watchedFraction,
            isWatched: item.isWatched,
            onPlay: isPlayable(item) ? { navigator.play(item, resumeFrom: item.resumePosition) } : nil,
            action: { navigator.show(.detail(item)) },
            menu: {
                if isPlayable(item) {
                    Button(item.resumePosition == nil ? "Play" : "Resume", systemImage: "play.fill") {
                        navigator.play(item, resumeFrom: item.resumePosition)
                    }
                }
                Button("Go to Details", systemImage: "info.circle") {
                    navigator.show(.detail(item))
                }
            }
        )
    }

    /// A series or season has no single thing to play, so it only goes to Detail.
    private func isPlayable(_ item: MediaItem) -> Bool {
        item.kind == .movie || item.kind == .episode
    }
}
