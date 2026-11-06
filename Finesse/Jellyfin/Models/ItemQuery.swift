import Foundation

/// What a library can be sorted by. Which of these suit which library is in `ItemSort.options(for:)`.
enum ItemSort: String, Hashable, Sendable, CaseIterable, Codable {
    case name = "SortName"
    case dateAdded = "DateCreated"
    case dateEpisodeAdded = "DateLastContentAdded"
    case releaseDate = "PremiereDate"
    case releaseYear = "ProductionYear"
    case communityRating = "CommunityRating"
    case criticRating = "CriticRating"
    case parentalRating = "OfficialRating"
    case runTime = "Runtime"
    case playCount = "PlayCount"
    case datePlayed = "DatePlayed"
    case bitrate = "VideoBitRate"
    case favourites = "IsFavoriteOrLiked"
    case watched = "IsPlayed"
    case random = "Random"
}

enum SortDirection: String, Hashable, Sendable, Codable {
    case ascending = "Ascending"
    case descending = "Descending"
}

/// A choice whose name differs from the value the server wants for it.
struct FilterValue: Identifiable, Hashable, Sendable, Codable {
    var id: String
    var name: String
}

enum ItemVideoType: String, Hashable, Sendable, CaseIterable, Codable {
    case bluRay = "BluRay"
    case dvd = "Dvd"
    case iso = "Iso"
}

enum ItemSeriesStatus: String, Hashable, Sendable, CaseIterable, Codable {
    case continuing = "Continuing"
    case ended = "Ended"
    case unreleased = "Unreleased"
}

/// Names by their first letter, ignoring a leading "The" as the server's sort name does.
enum NameFilter: Hashable, Sendable, Codable {
    case letter(String)
    /// Anything sorted before A, which is digits and symbols.
    case beforeA
}

/// Values within one list match any of them. Everything set here must match together, except that
/// the server treats 4K and HD or SD as any of them, because they are one question about size.
struct ItemFilter: Hashable, Sendable, Codable {
    var isPlayed: Bool?
    var isFavorite: Bool?
    var isResumable: Bool?
    var genres: [String] = []
    var years: [Int] = []
    var officialRatings: [String] = []
    var tags: [String] = []
    var studios: [FilterValue] = []
    var audioLanguages: [FilterValue] = []
    var subtitleLanguages: [FilterValue] = []
    var hasSubtitles = false
    var hasTrailer = false
    var hasSpecialFeature = false
    var hasThemeSong = false
    var hasThemeVideo = false
    var is3D = false
    var is4K = false
    /// True is HD and false is SD. They are one parameter, so the server can't take both.
    var isHD: Bool?
    var videoTypes: [ItemVideoType] = []
    var seriesStatuses: [ItemSeriesStatus] = []
    var minCommunityRating: Int?
    var name: NameFilter?
}

/// Query for one page of a library, or across all libraries when `libraryID` is nil.
struct ItemQuery: Hashable, Sendable {
    var libraryID: String?
    var kinds: [ItemKind] = []
    var recursive = true
    var searchTerm: String?
    /// Only these items, in whatever order the server likes.
    var ids: [String] = []
    var sort: ItemSort = .name
    var direction: SortDirection = .ascending
    var filter = ItemFilter()
    var startIndex = 0
    var limit = 50
}

/// The values a library offers for filtering. Studios are fetched separately because there are so many.
struct FilterOptions: Hashable, Sendable {
    var genres: [String] = []
    var years: [Int] = []
    var officialRatings: [String] = []
    var tags: [String] = []
    var audioLanguages: [FilterValue] = []
    var subtitleLanguages: [FilterValue] = []
}
