import Observation
import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case home
    case movies
    case shows
    case search
    case settings
}

/// A screen that can be pushed inside any tab.
enum AppRoute: Hashable {
    case detail(MediaItem)
}

/// What the player needs to start. A nil `resumePosition` plays from the beginning.
struct PlaybackRequest: Identifiable, Hashable {
    let id = UUID()
    var item: MediaItem
    var resumePosition: Ticks?
}

/// The one navigation API for feature code. Read it with `@Environment(AppNavigator.self)`.
@Observable
@MainActor
final class AppNavigator {
    var selectedTab = AppTab.home
    var paths: [AppTab: [AppRoute]] = [:]
    var activePlayback: PlaybackRequest?

    /// Pushes a screen on the current tab, so Back/Menu returns to where the user was.
    func show(_ route: AppRoute) {
        paths[selectedTab, default: []].append(route)
    }

    /// Starts the player over the current screen. This is the only way feature code starts playback.
    func play(_ item: MediaItem, resumeFrom position: Ticks? = nil) {
        activePlayback = PlaybackRequest(item: item, resumePosition: position)
    }
}
