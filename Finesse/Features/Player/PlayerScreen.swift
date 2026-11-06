import SwiftUI

/// Placeholder for the player, presented full screen by `MainTabView`. agent-3 replaces this,
/// keeping the name and the initialiser, or tells agent-1 what to change.
struct PlayerScreen: View {
    let request: PlaybackRequest

    var body: some View {
        EmptyStateView(
            title: request.item.name,
            message: "Player not built yet. Resume at \(Int(request.resumePosition?.seconds ?? 0)) seconds.",
            systemImage: "play.rectangle"
        )
    }
}
