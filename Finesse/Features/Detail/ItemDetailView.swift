import SwiftUI

/// Placeholder route for `AppRoute.detail`. agent-2 replaces this.
struct ItemDetailView: View {
    @Environment(AppNavigator.self) private var navigator
    let item: MediaItem

    var body: some View {
        VStack(spacing: 40) {
            Text(item.name).font(.title)
            Button("Play") { navigator.play(item, resumeFrom: item.resumePosition) }
        }
    }
}
