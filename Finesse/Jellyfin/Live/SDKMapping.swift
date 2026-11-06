import Foundation
import JellyfinAPI

// The only place SDK entities turn into app models. Nothing outside Finesse/Jellyfin/Live imports JellyfinAPI.

extension Ticks {
    init?(_ value: Int?) {
        guard let value else { return nil }
        self.init(rawValue: Int64(value))
    }
}

extension ItemKind {
    init(_ kind: BaseItemKind?) {
        switch kind {
        case .movie: self = .movie
        case .series: self = .series
        case .season: self = .season
        case .episode: self = .episode
        default: self = .other(kind?.rawValue ?? "")
        }
    }

    /// Nil for kinds the app has no use for querying.
    var sdkKind: BaseItemKind? {
        switch self {
        case .movie: .movie
        case .series: .series
        case .season: .season
        case .episode: .episode
        case .other(let raw): BaseItemKind(rawValue: raw)
        }
    }
}

extension UserItemState {
    init(_ dto: UserItemDataDto?) {
        self.init(
            playbackPosition: Ticks(dto?.playbackPositionTicks) ?? .zero,
            playedPercentage: dto?.playedPercentage,
            isPlayed: dto?.isPlayed ?? false,
            isFavorite: dto?.isFavorite ?? false,
            unplayedItemCount: dto?.unplayedItemCount
        )
    }
}

extension MediaItem {
    init(_ dto: BaseItemDto) {
        self.init(
            id: dto.id ?? "",
            name: dto.name ?? "",
            kind: ItemKind(dto.type),
            overview: dto.overview,
            tagline: dto.taglines?.first,
            productionYear: dto.productionYear,
            premiereDate: dto.premiereDate,
            runTime: Ticks(dto.runTimeTicks),
            communityRating: dto.communityRating.map(Double.init),
            criticRating: dto.criticRating.map(Double.init),
            officialRating: dto.officialRating,
            genres: dto.genres ?? [],
            studios: dto.studios?.compactMap(\.name) ?? [],
            people: dto.people?.compactMap(Person.init) ?? [],
            images: ItemImages(
                primaryTag: dto.imageTags?["Primary"],
                thumbTag: dto.imageTags?["Thumb"],
                logoTag: dto.imageTags?["Logo"],
                backdropTags: dto.backdropImageTags ?? [],
                seriesPrimaryTag: dto.seriesPrimaryImageTag,
                seriesThumbTag: dto.seriesThumbImageTag,
                parentBackdropItemID: dto.parentBackdropItemID,
                parentBackdropTags: dto.parentBackdropImageTags ?? []
            ),
            userState: UserItemState(dto.userData),
            seriesID: dto.seriesID,
            seriesName: dto.seriesName,
            seasonID: dto.seasonID,
            seasonName: dto.seasonName,
            indexNumber: dto.indexNumber,
            parentIndexNumber: dto.parentIndexNumber,
            childCount: dto.childCount
        )
    }
}

extension Person {
    init?(_ dto: BaseItemPerson) {
        guard let id = dto.id, let name = dto.name else { return nil }
        self.init(id: id, name: name, role: dto.role, type: dto.type?.rawValue, primaryImageTag: dto.primaryImageTag)
    }
}

extension Library {
    init(_ dto: BaseItemDto) {
        let kind: LibraryKind = switch dto.collectionType?.rawValue {
        case "movies": .movies
        case "tvshows": .shows
        case let other: .other(other ?? "")
        }
        self.init(id: dto.id ?? "", name: dto.name ?? "", kind: kind, primaryImageTag: dto.imageTags?["Primary"])
    }
}

extension MediaSegmentKind {
    init(_ type: MediaSegmentType?) {
        switch type {
        case .intro: self = .intro
        case .outro: self = .outro
        case .recap: self = .recap
        case .preview: self = .preview
        case .commercial: self = .commercial
        default: self = .unknown
        }
    }
}

extension MediaSegment {
    init?(_ dto: MediaSegmentDto) {
        guard let id = dto.id, let itemID = dto.itemID, let start = Ticks(dto.startTicks), let end = Ticks(dto.endTicks)
        else { return nil }
        self.init(id: id, itemID: itemID, kind: MediaSegmentKind(dto.type), start: start, end: end)
    }
}

extension MediaStreamKind {
    init(_ type: MediaStreamType?) {
        switch type {
        case .video: self = .video
        case .audio: self = .audio
        case .subtitle: self = .subtitle
        default: self = .other(type?.rawValue ?? "")
        }
    }
}

extension MediaStreamInfo {
    init(_ dto: MediaStream, resolve: (String?) -> URL?) {
        self.init(
            index: dto.index ?? -1,
            kind: MediaStreamKind(dto.type),
            codec: dto.codec,
            language: dto.language,
            title: dto.title,
            displayTitle: dto.displayTitle,
            isDefault: dto.isDefault ?? false,
            isForced: dto.isForced ?? false,
            isExternal: dto.isExternal ?? false,
            isTextSubtitle: dto.isTextSubtitleStream ?? false,
            deliveryURL: resolve(dto.deliveryURL),
            channels: dto.channels,
            bitRate: dto.bitRate,
            width: dto.width,
            height: dto.height,
            frameRate: (dto.realFrameRate ?? dto.averageFrameRate).map(Double.init),
            bitDepth: dto.bitDepth,
            profile: dto.profile,
            videoRangeType: dto.videoRangeType?.rawValue
        )
    }
}

extension JellyfinAPI.PlayMethod {
    init(_ method: PlayMethod) {
        switch method {
        case .directPlay: self = .directPlay
        case .directStream: self = .directStream
        case .transcode: self = .transcode
        }
    }
}

extension PlaybackStateInfo {
    init(_ report: PlaybackReport) {
        self.init(
            audioStreamIndex: report.audioStreamIndex,
            canSeek: true,
            isMuted: report.isMuted,
            isPaused: report.isPaused,
            itemID: report.itemID,
            liveStreamID: report.liveStreamID,
            mediaSourceID: report.mediaSourceID,
            playMethod: JellyfinAPI.PlayMethod(report.playMethod),
            playSessionID: report.playSessionID,
            positionTicks: Int(report.position.rawValue),
            subtitleStreamIndex: report.subtitleStreamIndex
        )
    }
}

extension JellyfinAPI.DeviceProfile {
    /// The app's profile uses Jellyfin's wire names, so converting is a JSON round trip.
    /// A value the server's schema does not allow fails here rather than at the server.
    init(_ profile: DeviceProfile) throws {
        let data = try JSONEncoder().encode(profile)
        self = try JSONDecoder().decode(JellyfinAPI.DeviceProfile.self, from: data)
    }
}
