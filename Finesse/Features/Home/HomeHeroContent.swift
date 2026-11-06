import Foundation

/// What the billboard shows for one item. It's built from the item and its series, so a view never
/// has to decide what would give an unwatched episode away.
struct HomeHeroContent: Equatable {
    /// What More Info opens.
    let item: MediaItem
    let title: String
    /// The episode's own name, once it's safe to show.
    let subtitle: String?
    let logoURL: URL?
    let backdropURL: URL?
    let metadata: [String]
    let genres: [String]
    let overview: String?
    /// What Play starts. A nil value leaves only More Info.
    let playTarget: MediaItem?

    /// `full` is the item's own full record and `series` its series, when they could be loaded.
    init(
        item: MediaItem,
        full: MediaItem?,
        series: MediaItem?,
        playTarget: MediaItem?,
        client: any JellyfinClient
    ) {
        // The list's copy has the current watch state, and the full record has the details.
        var details = full ?? item
        details.userState = item.userState
        self.item = item
        self.playTarget = playTarget

        let isEpisode = item.kind == .episode || item.kind == .season
        title = isEpisode ? details.seriesName ?? series?.name ?? details.name : details.name
        logoURL = client.imageURL(
            itemID: series?.id ?? details.id,
            kind: .logo,
            tag: (series ?? details).images.logoTag,
            index: nil,
            maxWidth: 1000
        )
        backdropURL = client.homeBackdropURL(for: details, series: series)
        metadata = details.detailMetadata
        genres = Array((details.genres.isEmpty ? series?.genres ?? [] : details.genres).prefix(3))

        if details.mightSpoil {
            subtitle = nil
            overview = series?.overview
        } else {
            subtitle = item.kind == .episode ? details.name : nil
            overview = details.overview ?? series?.overview
        }
    }

    var playTitle: String {
        playTarget?.resumePosition == nil ? "Play" : "Resume"
    }
}

extension MediaItem {
    /// An episode nobody has started. Its still, name and overview can all give the story away.
    var mightSpoil: Bool {
        kind == .episode && !userState.isPlayed && userState.playbackPosition == .zero
    }
}

extension JellyfinClient {
    /// The full-screen art behind Home. An episode only ever uses its series' art, never its own
    /// still, and a poster is left out because it doesn't fill a 16:9 screen.
    func homeBackdropURL(for item: MediaItem, series: MediaItem? = nil, maxWidth: Int = 1920) -> URL? {
        let images = item.images
        if item.kind != .episode, item.kind != .season {
            if let tag = images.backdropTags.first {
                return imageURL(itemID: item.id, kind: .backdrop, tag: tag, index: 0, maxWidth: maxWidth)
            }
            return imageURL(itemID: item.id, kind: .thumb, tag: images.thumbTag, index: nil, maxWidth: maxWidth)
        }
        if let parent = images.parentBackdropItemID, let tag = images.parentBackdropTags.first {
            return imageURL(itemID: parent, kind: .backdrop, tag: tag, index: 0, maxWidth: maxWidth)
        }
        if let series, let tag = series.images.backdropTags.first {
            return imageURL(itemID: series.id, kind: .backdrop, tag: tag, index: 0, maxWidth: maxWidth)
        }
        return nil
    }
}
