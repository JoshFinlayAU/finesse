import Foundation

enum ItemKind: Hashable, Sendable, Codable {
    case movie
    case series
    case season
    case episode
    case other(String)
}

enum ImageKind: String, Hashable, Sendable, Codable {
    case primary = "Primary"
    case backdrop = "Backdrop"
    case thumb = "Thumb"
    case logo = "Logo"
    case chapter = "Chapter"
}

/// Cache tags for the images an item has. A nil tag means the item has no image of that kind.
struct ItemImages: Hashable, Sendable, Codable {
    var primaryTag: String?
    var thumbTag: String?
    var logoTag: String?
    var backdropTags: [String] = []
    /// Images inherited from the series, for seasons and episodes.
    var seriesPrimaryTag: String?
    var seriesThumbTag: String?
    var parentBackdropItemID: String?
    var parentBackdropTags: [String] = []
}

struct UserItemState: Hashable, Sendable, Codable {
    var playbackPosition: Ticks = .zero
    var playedPercentage: Double?
    var isPlayed = false
    var isFavorite = false
    var unplayedItemCount: Int?
}

struct Person: Identifiable, Hashable, Sendable, Codable {
    var id: String
    var name: String
    var role: String?
    var type: String?
    var primaryImageTag: String?
}

struct MediaItem: Identifiable, Hashable, Sendable, Codable {
    var id: String
    var name: String
    var kind: ItemKind
    var overview: String?
    var tagline: String?
    var productionYear: Int?
    var premiereDate: Date?
    var runTime: Ticks?
    var communityRating: Double?
    var criticRating: Double?
    var officialRating: String?
    var genres: [String] = []
    var studios: [String] = []
    var people: [Person] = []
    var images = ItemImages()
    var userState = UserItemState()

    var seriesID: String?
    var seriesName: String?
    var seasonID: String?
    var seasonName: String?
    /// Episode number within the season, or season number for a season.
    var indexNumber: Int?
    /// Season number for an episode.
    var parentIndexNumber: Int?
    var childCount: Int?
}

enum LibraryKind: Hashable, Sendable, Codable {
    case movies
    case shows
    case other(String)
}

struct Library: Identifiable, Hashable, Sendable, Codable {
    var id: String
    var name: String
    var kind: LibraryKind
    var primaryImageTag: String?
}

struct Page<Element: Sendable>: Sendable {
    var items: [Element]
    var startIndex: Int
    var totalCount: Int

    var hasMore: Bool {
        startIndex + items.count < totalCount
    }
}

extension Page: Equatable where Element: Equatable {}

enum MediaSegmentKind: Hashable, Sendable {
    case intro
    case outro
    case recap
    case preview
    case commercial
    case unknown
}

/// A chapter of an item. `imageTag` is nil unless the server has extracted chapter images.
struct ItemChapter: Identifiable, Hashable, Sendable {
    var index: Int
    var name: String?
    var start: Ticks
    var imageTag: String?

    var id: Int { index }
}

struct MediaSegment: Identifiable, Hashable, Sendable {
    var id: String
    var itemID: String
    var kind: MediaSegmentKind
    var start: Ticks
    var end: Ticks
}
