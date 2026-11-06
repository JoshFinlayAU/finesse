import SwiftUI

/// Placeholder route for the Movies and TV Shows tabs. agent-2 replaces this.
struct LibraryRootView: View {
    let kind: LibraryKind

    var body: some View {
        EmptyStateView(title: kind == .movies ? "Movies" : "TV Shows", message: "Coming soon.")
    }
}
