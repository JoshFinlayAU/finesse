import SwiftUI
import UIKit

/// Loads artwork through a disposable cache. Jellyfin image URLs carry the image tag, so a cached
/// copy stays valid until the artwork changes, and the system may purge the disk copy at any time.
final class ImagePipeline: Sendable {
    static let shared = ImagePipeline()

    private let memory = ImageMemoryCache()
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            directory: URL.cachesDirectory.appending(path: "Artwork")
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-FinesseFakeServer") {
            configuration.protocolClasses = [FakeArtworkProtocol.self]
        }
        #endif
        session = URLSession(configuration: configuration)
    }

    func cachedImage(for url: URL) -> UIImage? {
        memory.image(for: url)
    }

    func image(for url: URL) async throws -> UIImage {
        if let cached = memory.image(for: url) { return cached }
        #if DEBUG
        Self.recordRequest()
        #endif
        let (data, _) = try await session.data(from: url)
        guard let decoded = await UIImage(data: data)?.byPreparingForDisplay() else {
            throw URLError(.cannotDecodeContentData)
        }
        memory.insert(decoded, for: url)
        return decoded
    }
}

#if DEBUG
extension ImagePipeline {
    /// Adds a line per image fetched, with no address, so a UI test can count what a screen loads.
    private static func recordRequest() {
        guard let path = ProcessInfo.processInfo.environment["FINESSE_IMAGE_REQUEST_LOG"],
              let file = FileHandle(forWritingAtPath: path)
        else { return }
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: Data("1\n".utf8))
    }
}
#endif

/// NSCache is documented as thread-safe but is not marked Sendable.
private final class ImageMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSURL, UIImage>()

    init() {
        cache.totalCostLimit = 256 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale) * 4
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

/// Artwork that fills its frame, with a quiet placeholder while loading or when there is no image.
struct CachedImage: View {
    let url: URL?
    var placeholderSymbol = "photo"

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = ImagePipeline.shared.cachedImage(for: url)
            guard image == nil else { return }
            image = try? await ImagePipeline.shared.image(for: url)
        }
    }
}
