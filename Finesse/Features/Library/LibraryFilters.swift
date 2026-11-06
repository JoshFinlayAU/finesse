import Foundation

extension ItemSort {
    var title: String {
        switch self {
        case .name: "Name"
        case .dateAdded: "Date Added"
        case .dateEpisodeAdded: "Date Episode Added"
        case .releaseDate: "Release Date"
        case .releaseYear: "Release Year"
        case .communityRating: "Community Rating"
        case .criticRating: "Critic Rating"
        case .parentalRating: "Parental Rating"
        case .runTime: "Runtime"
        case .playCount: "Play Count"
        case .datePlayed: "Date Played"
        case .bitrate: "Video Bitrate"
        case .favourites: "Favourites"
        case .watched: "Watched"
        case .random: "Random"
        }
    }

    /// Names read A to Z. Everything else reads best with the newest or highest first.
    var naturalDirection: SortDirection {
        self == .name ? .ascending : .descending
    }

    /// Tested against the server for each library. Critic rating has no values on series, date
    /// episode added does nothing on movies, and bitrate does nothing on series.
    static func options(for kind: ItemKind) -> [ItemSort] {
        var sorts: [ItemSort] = [.name, .dateAdded]
        if kind == .series {
            sorts.append(.dateEpisodeAdded)
        }
        sorts += [.releaseDate, .releaseYear, .communityRating]
        if kind == .movie {
            sorts.append(.criticRating)
        }
        sorts += [.parentalRating, .runTime, .playCount, .datePlayed]
        if kind == .movie {
            sorts.append(.bitrate)
        }
        return sorts + [.favourites, .watched, .random]
    }
}

/// One on or off choice in the filter panel. Each is offered only if it narrows the library.
enum FilterChoice: Hashable, Sendable {
    case unwatched, watched, inProgress
    case favourites
    case fourK, hd, sd
    case threeD
    case subtitles, trailer, specialFeature, themeSong, themeVideo
    case videoType(ItemVideoType)
    case seriesStatus(ItemSeriesStatus)
    case minimumRating(Int)

    static let ratings = [9, 8, 7, 6, 5]

    static func all(for kind: ItemKind) -> [FilterChoice] {
        var choices: [FilterChoice] = [
            .unwatched, .watched, .inProgress, .favourites,
            .fourK, .hd, .sd, .threeD,
            .subtitles, .trailer, .specialFeature, .themeSong, .themeVideo,
        ]
        choices += ItemVideoType.allCases.map(FilterChoice.videoType)
        if kind == .series {
            choices += ItemSeriesStatus.allCases.map(FilterChoice.seriesStatus)
        }
        return choices + ratings.map(FilterChoice.minimumRating)
    }

    var title: String {
        switch self {
        case .unwatched: "Unwatched"
        case .watched: "Watched"
        case .inProgress: "In Progress"
        case .favourites: "Favourites"
        case .fourK: "4K"
        case .hd: "HD"
        case .sd: "SD"
        case .threeD: "3D"
        case .subtitles: "Subtitles"
        case .trailer: "Trailer"
        case .specialFeature: "Special Features"
        case .themeSong: "Theme Song"
        case .themeVideo: "Theme Video"
        case .videoType(.bluRay): "Blu-ray"
        case .videoType(.dvd): "DVD"
        case .videoType(.iso): "ISO"
        case .seriesStatus(.continuing): "Continuing"
        case .seriesStatus(.ended): "Ended"
        case .seriesStatus(.unreleased): "Unreleased"
        case .minimumRating(let rating): "\(rating) or Higher"
        }
    }

    func isOn(in filter: ItemFilter) -> Bool {
        switch self {
        case .unwatched: filter.isPlayed == false
        case .watched: filter.isPlayed == true
        case .inProgress: filter.isResumable == true
        case .favourites: filter.isFavorite == true
        case .fourK: filter.is4K
        case .hd: filter.isHD == true
        case .sd: filter.isHD == false
        case .threeD: filter.is3D
        case .subtitles: filter.hasSubtitles
        case .trailer: filter.hasTrailer
        case .specialFeature: filter.hasSpecialFeature
        case .themeSong: filter.hasThemeSong
        case .themeVideo: filter.hasThemeVideo
        case .videoType(let type): filter.videoTypes.contains(type)
        case .seriesStatus(let status): filter.seriesStatuses.contains(status)
        case .minimumRating(let rating): filter.minCommunityRating == rating
        }
    }

    /// Turns it on or off. Choices the server can't take together replace each other: asking for
    /// watched and unwatched is a 400, and HD and SD are one parameter.
    func toggle(in filter: inout ItemFilter) {
        let on = !isOn(in: filter)
        switch self {
        case .unwatched, .watched, .inProgress:
            filter.isPlayed = nil
            filter.isResumable = nil
            if on {
                switch self {
                case .unwatched: filter.isPlayed = false
                case .watched: filter.isPlayed = true
                default: filter.isResumable = true
                }
            }
        case .favourites: filter.isFavorite = on ? true : nil
        case .fourK: filter.is4K = on
        case .hd: filter.isHD = on ? true : nil
        case .sd: filter.isHD = on ? false : nil
        case .threeD: filter.is3D = on
        case .subtitles: filter.hasSubtitles = on
        case .trailer: filter.hasTrailer = on
        case .specialFeature: filter.hasSpecialFeature = on
        case .themeSong: filter.hasThemeSong = on
        case .themeVideo: filter.hasThemeVideo = on
        case .videoType(let type):
            filter.videoTypes = on ? filter.videoTypes + [type] : filter.videoTypes.filter { $0 != type }
        case .seriesStatus(let status):
            filter.seriesStatuses = on ? filter.seriesStatuses + [status] : filter.seriesStatuses.filter { $0 != status }
        case .minimumRating(let rating):
            filter.minCommunityRating = on ? rating : nil
        }
    }
}

/// A list of values the server supplies, where any selected one matches.
enum FilterList: String, Hashable, Sendable, CaseIterable {
    case genres, years, parentalRatings, tags, studios, audioLanguages, subtitleLanguages

    var title: String {
        switch self {
        case .genres: "Genres"
        case .years: "Years"
        case .parentalRatings: "Parental Ratings"
        case .tags: "Tags"
        case .studios: "Studios"
        case .audioLanguages: "Audio Languages"
        case .subtitleLanguages: "Subtitle Languages"
        }
    }

    func values(in options: FilterOptions, studios: [FilterValue]) -> [FilterValue] {
        switch self {
        case .genres: options.genres.map { FilterValue(id: $0, name: $0) }
        case .years: options.years.map { FilterValue(id: String($0), name: String($0)) }
        case .parentalRatings: options.officialRatings.map { FilterValue(id: $0, name: $0) }
        case .tags: options.tags.map { FilterValue(id: $0, name: $0) }
        case .studios: studios
        case .audioLanguages: options.audioLanguages
        case .subtitleLanguages: options.subtitleLanguages
        }
    }

    func selected(in filter: ItemFilter) -> [FilterValue] {
        switch self {
        case .genres: filter.genres.map { FilterValue(id: $0, name: $0) }
        case .years: filter.years.map { FilterValue(id: String($0), name: String($0)) }
        case .parentalRatings: filter.officialRatings.map { FilterValue(id: $0, name: $0) }
        case .tags: filter.tags.map { FilterValue(id: $0, name: $0) }
        case .studios: filter.studios
        case .audioLanguages: filter.audioLanguages
        case .subtitleLanguages: filter.subtitleLanguages
        }
    }

    func set(_ values: [FilterValue], in filter: inout ItemFilter) {
        switch self {
        case .genres: filter.genres = values.map(\.id)
        case .years: filter.years = values.compactMap { Int($0.id) }
        case .parentalRatings: filter.officialRatings = values.map(\.id)
        case .tags: filter.tags = values.map(\.id)
        case .studios: filter.studios = values
        case .audioLanguages: filter.audioLanguages = values
        case .subtitleLanguages: filter.subtitleLanguages = values
        }
    }

    func toggle(_ value: FilterValue, in filter: inout ItemFilter) {
        let current = selected(in: filter)
        let isOn = current.contains { $0.id == value.id }
        set(isOn ? current.filter { $0.id != value.id } : current + [value], in: &filter)
    }
}

extension ItemFilter {
    /// What's active, one entry per selected value, in the order the panel shows them.
    func activeTitles(kind: ItemKind) -> [String] {
        var titles = FilterChoice.all(for: kind).filter { $0.isOn(in: self) }.map(\.title)
        switch name {
        case .letter(let letter): titles.append("Starts with \(letter)")
        case .beforeA: titles.append("Starts with #")
        case nil: break
        }
        for list in FilterList.allCases {
            titles += list.selected(in: self).map { value in
                // English audio and English subtitles would otherwise read the same.
                switch list {
                case .audioLanguages: "\(value.name) Audio"
                case .subtitleLanguages: "\(value.name) Subtitles"
                default: value.name
                }
            }
        }
        return titles
    }
}

/// A library's sort and filters, remembered per user. Losing this only resets the view.
struct LibraryPreferences: Codable, Hashable {
    var sort = ItemSort.name
    var direction = SortDirection.ascending
    var filter = ItemFilter()
}

struct LibraryPreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, account: String, kind: ItemKind) {
        self.defaults = defaults
        key = "libraryPreferences.\(account).\(kind == .movie ? "movie" : "series")"
    }

    func load() -> LibraryPreferences? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(LibraryPreferences.self, from: $0) }
    }

    func save(_ preferences: LibraryPreferences) {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: key)
        }
    }
}
