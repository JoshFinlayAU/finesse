import Foundation
import TVServices

/// One row of the Top Shelf, free of TVServices so the rules can be tested directly.
struct TopShelfSection: Equatable, Sendable {
    var title: String
    var entries: [TopShelfEntry]
}

struct TopShelfEntry: Equatable, Sendable {
    enum Shape: Sendable {
        case poster
        case landscape
    }

    var id: String
    var title: String
    var imageURL: URL?
    var shape: Shape
    /// From 0 to 1, or nil when there's nothing to show.
    var progress: Double?
    var playLink: FinesseDeepLink
    var displayLink: FinesseDeepLink
}

enum TopShelfContent {
    static let itemsPerSection = 12

    /// The active user's sections, with empty ones left out. Nil means show the static image: the
    /// token was refused, the server can't be reached, or there's nothing to show.
    static func sections(client: any JellyfinClient, account: String) async -> [TopShelfSection]? {
        async let resume = result { try await client.resumeItems(limit: itemsPerSection) }
        async let nextUp = result { try await client.nextUp(limit: itemsPerSection) }
        async let latest = result { try await client.latestItems(libraryID: nil, limit: itemsPerSection) }
        let results = await (resume, nextUp, latest)

        let all = [results.0, results.1, results.2]
        let isExpired = all.contains { result in
            if case .failure(let error) = result, (error as? JellyfinError) == .notSignedIn { return true }
            return false
        }
        guard !isExpired else {
            return nil
        }

        var shown = Set<String>()
        func section(_ title: String, _ result: Result<[MediaItem], any Error>, _ shape: TopShelfEntry.Shape) -> TopShelfSection? {
            let items = (try? result.get()) ?? []
            // A title shows once, in the first row that has it.
            let entries = items
                .filter { shown.insert($0.id).inserted }
                .map { entry(for: $0, shape: shape, client: client, account: account) }
            return entries.isEmpty ? nil : TopShelfSection(title: title, entries: entries)
        }
        let sections = [
            section("Continue Watching", results.0, .landscape),
            section("Next Up", results.1, .landscape),
            section("Recently Added", results.2, .poster),
        ].compactMap { $0 }
        return sections.isEmpty ? nil : sections
    }

    private static func result<Value>(_ work: () async throws -> Value) async -> Result<Value, any Error> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }

    private static func entry(
        for item: MediaItem,
        shape: TopShelfEntry.Shape,
        client: any JellyfinClient,
        account: String
    ) -> TopShelfEntry {
        TopShelfEntry(
            id: item.id,
            title: item.kind == .episode ? [item.cardTitle, item.cardSubtitle].compactMap { $0 }.joined(separator: " ") : item.cardTitle,
            imageURL: shape == .poster ? client.posterURL(for: item) : client.landscapeURL(for: item),
            shape: shape,
            progress: item.watchedFraction,
            playLink: FinesseDeepLink(action: .play, itemID: item.id, account: account),
            displayLink: FinesseDeepLink(action: .detail, itemID: item.id, account: account)
        )
    }

    /// What the system draws.
    static func shelf(_ sections: [TopShelfSection]) -> TVTopShelfSectionedContent {
        TVTopShelfSectionedContent(sections: sections.map { section in
            let collection = TVTopShelfItemCollection(items: section.entries.map(item))
            collection.title = section.title
            return collection
        })
    }

    private static func item(_ entry: TopShelfEntry) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: entry.id)
        item.title = entry.title
        item.imageShape = entry.shape == .poster ? .poster : .hdtv
        if let url = entry.imageURL {
            item.setImageURL(url, for: [.screenScale1x, .screenScale2x])
        }
        if let progress = entry.progress {
            item.playbackProgress = progress
        }
        item.playAction = entry.playLink.url.map(TVTopShelfAction.init)
        item.displayAction = entry.displayLink.url.map(TVTopShelfAction.init)
        return item
    }
}
