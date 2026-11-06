import Foundation

extension MediaItem {
    /// The main line on a card. Episodes lead with their series.
    var cardTitle: String {
        kind == .episode ? seriesName ?? name : name
    }

    var cardSubtitle: String? {
        switch kind {
        case .episode:
            var parts: [String] = []
            if let parentIndexNumber { parts.append("S\(parentIndexNumber)") }
            if let indexNumber { parts.append("E\(indexNumber)") }
            let number = parts.joined(separator: " ")
            return number.isEmpty ? name : "\(number) · \(name)"
        default:
            return productionYear.map(String.init)
        }
    }

    /// Watched fraction from 0 to 1, or nil when there is no partial progress to show.
    var watchedFraction: Double? {
        guard !userState.isPlayed, userState.playbackPosition > .zero else { return nil }
        if let percentage = userState.playedPercentage {
            return percentage / 100
        }
        guard let runTime, runTime > .zero else { return nil }
        return userState.playbackPosition.seconds / runTime.seconds
    }

    /// The saved position to resume from, or nil to play from the start.
    var resumePosition: Ticks? {
        userState.playbackPosition > .zero ? userState.playbackPosition : nil
    }
}

extension JellyfinClient {
    /// Portrait artwork. Episodes and seasons fall back to their series poster.
    func posterURL(for item: MediaItem, maxWidth: Int = 520) -> URL? {
        if item.kind != .episode, item.images.primaryTag != nil {
            return imageURL(itemID: item.id, kind: .primary, tag: item.images.primaryTag, index: nil, maxWidth: maxWidth)
        }
        if let seriesID = item.seriesID, item.images.seriesPrimaryTag != nil {
            return imageURL(itemID: seriesID, kind: .primary, tag: item.images.seriesPrimaryTag, index: nil, maxWidth: maxWidth)
        }
        return imageURL(itemID: item.id, kind: .primary, tag: item.images.primaryTag, index: nil, maxWidth: maxWidth)
    }

    /// 16:9 artwork. An episode's primary image is already a still, otherwise prefer a thumb or backdrop.
    func landscapeURL(for item: MediaItem, maxWidth: Int = 880) -> URL? {
        let images = item.images
        if item.kind == .episode, images.primaryTag != nil {
            return imageURL(itemID: item.id, kind: .primary, tag: images.primaryTag, index: nil, maxWidth: maxWidth)
        }
        if images.thumbTag != nil {
            return imageURL(itemID: item.id, kind: .thumb, tag: images.thumbTag, index: nil, maxWidth: maxWidth)
        }
        if let tag = images.backdropTags.first {
            return imageURL(itemID: item.id, kind: .backdrop, tag: tag, index: 0, maxWidth: maxWidth)
        }
        if let seriesID = item.seriesID, images.seriesThumbTag != nil {
            return imageURL(itemID: seriesID, kind: .thumb, tag: images.seriesThumbTag, index: nil, maxWidth: maxWidth)
        }
        if let parent = images.parentBackdropItemID, let tag = images.parentBackdropTags.first {
            return imageURL(itemID: parent, kind: .backdrop, tag: tag, index: 0, maxWidth: maxWidth)
        }
        return imageURL(itemID: item.id, kind: .primary, tag: images.primaryTag, index: nil, maxWidth: maxWidth)
    }
}
