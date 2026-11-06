import SwiftUI

struct MainTabView: View {
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
