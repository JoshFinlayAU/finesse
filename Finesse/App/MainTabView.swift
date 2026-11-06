import SwiftUI

struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.jellyfinClient) private var client
    @State private var navigator = AppNavigator()

    var body: some View {
        @Bindable var navigator = navigator
        TabView(selection: $navigator.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                stack(for: .home) { HomeView() }
            }
            Tab("Movies", systemImage: "film", value: AppTab.movies) {
                stack(for: .movies) { LibraryRootView(kind: .movies) }
            }
            Tab("TV Shows", systemImage: "tv", value: AppTab.shows) {
                stack(for: .shows) { LibraryRootView(kind: .shows) }
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                stack(for: .search) { SearchRootView() }
            }
            Tab("Settings", systemImage: "person.crop.circle", value: AppTab.settings) {
                stack(for: .settings) { AccountView() }
            }
        }
        .environment(navigator)
        .fullScreenCover(item: $navigator.activePlayback) { request in
            PlayerScreen(request: request)
                .environment(navigator)
        }
        .task(id: app.pendingLink) { await openPendingLink() }
    }

    /// Here because the navigator lives here. A switch to another user rebuilds this view, so the
    /// link for them is picked up by the new one.
    private func openPendingLink() async {
        guard let link = app.pendingLink, link.account == app.session?.accountKey else {
            return
        }
        do {
            try await navigator.open(link, client: client)
            app.finishLink()
        } catch is CancellationError {
            return
        } catch JellyfinError.notSignedIn {
            app.finishLink()
            app.sessionExpired()
        } catch JellyfinError.notFound {
            app.finishLink()
            app.linkError = "That's no longer on the server."
        } catch {
            app.finishLink()
            app.linkError = error.userMessage
        }
    }

    private func stack<Content: View>(for tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: Binding(
            get: { navigator.paths[tab] ?? [] },
            set: { navigator.paths[tab] = $0 }
        )) {
            content()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .detail(let item):
                        ItemDetailView(item: item)
                    }
                }
        }
    }
}
