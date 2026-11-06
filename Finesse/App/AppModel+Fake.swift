#if DEBUG
import Foundation
import UIKit

extension AppModel {
    /// Launch with `-FinesseFakeServer` for two signed-in users and seeded hubs with no server.
    /// The test server has one test user, so this is how switching between users gets exercised.
    static func fakeServer() -> AppModel {
        let url = URL(string: "http://fake.invalid:8096")!
        let client = InMemoryJellyfinClient(serverURL: url)
        let storage = FakeServerStorage()
        let store = SessionStore(storage: storage)
        var accounts = StoredAccounts()
        for (id, name) in [("bob", "Bob"), ("alice", "Alice")] {
            accounts.upsert(UserSession(
                serverURL: url,
                serverID: "fake-server",
                user: User(id: id, name: name),
                accessToken: "fake-\(id)"
            ))
        }
        try? store.save(accounts)
        Task {
            await client.configure {
                var resume = MediaItem(id: "resume", name: "A Film in Progress", kind: .movie)
                resume.runTime = Ticks(seconds: 6000)
                resume.userState.playbackPosition = Ticks(seconds: 1500)
                resume.productionYear = 2024
                resume.overview = "A dark film, so the billboard can be checked over dark art."
                resume.genres = ["Drama"]
                resume.images.backdropTags = ["dark"]
                var show = MediaItem(id: "a-long-show", name: "A Long Show", kind: .series)
                show.overview = "What the whole show is about, and safe to read."
                show.genres = ["Comedy"]
                show.images.backdropTags = ["bright"]
                show.images.primaryTag = "poster"
                var next = MediaItem(id: "next", name: "The Next One", kind: .episode)
                next.seriesID = "a-long-show"
                next.seriesName = "A Long Show"
                next.parentIndexNumber = 2
                next.indexNumber = 5
                next.overview = "A secret that this episode gives away."
                next.images.primaryTag = "still"
                next.images.parentBackdropItemID = show.id
                next.images.parentBackdropTags = ["bright"]
                $0.resumeValue = [resume]
                $0.nextUpValue = [next]
                $0.latestValue = (1...8).map { index in
                    var film = MediaItem(id: "new-\(index)", name: "New Film \(index)", kind: .movie)
                    film.productionYear = 2026
                    film.overview = "Film \(index). The odd ones have bright art and the even ones dark, with long enough text to fill the lines this space gives it, so its readability is easy to judge."
                    film.genres = ["Drama"]
                    film.images.primaryTag = "poster"
                    film.images.backdropTags = [index.isMultiple(of: 2) ? "dark" : "bright"]
                    // The rest have no logo, to show the title as text.
                    if index == 1 { film.images.logoTag = "logo" }
                    return film
                }
                $0.allItems = [resume, next, show] + $0.latestValue
                $0.filterOptionsValue.genres = ["Drama"]
                // `-FinesseFakeServerFails` makes every request fail, to show the error states.
                if ProcessInfo.processInfo.arguments.contains("-FinesseFakeServerFails") {
                    $0.failure = .network("Seeded failure")
                }
            }
        }
        return AppModel(
            store: store,
            identity: DeviceIdentity(clientName: "Finesse", clientVersion: "0", deviceName: "Fake", deviceID: "fake"),
            makeClient: { _, _ in client }
        )
    }
}

/// Draws artwork for the fake server, so Home can be judged over very bright and very dark images.
final class FakeArtworkProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "fake.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let data = Self.art(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func art(for url: URL) -> Data? {
        let parts = url.pathComponents
        guard let images = parts.firstIndex(of: "Images"), images > 0, parts.count > images + 1 else { return nil }
        let id = parts[images - 1]
        switch parts[images + 1] {
        case "Logo":
            let format = UIGraphicsImageRendererFormat()
            format.opaque = false
            return UIGraphicsImageRenderer(size: CGSize(width: 800, height: 240), format: format).pngData { _ in
                "FAKE LOGO".draw(at: CGPoint(x: 0, y: 40), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 130, weight: .black),
                    .foregroundColor: UIColor.white,
                ])
            }
        case "Backdrop":
            let number = id.split(separator: "-").last.flatMap { Int($0) } ?? 0
            let isBright = id == "a-long-show" || (id.hasPrefix("new-") && !number.isMultiple(of: 2))
            return gradient(
                size: CGSize(width: 1280, height: 720),
                from: isBright ? .white : UIColor(white: 0.04, alpha: 1),
                to: isBright ? UIColor(red: 1, green: 0.95, blue: 0.75, alpha: 1) : UIColor(white: 0.12, alpha: 1)
            )
        default:
            return gradient(
                size: CGSize(width: 400, height: 600),
                from: UIColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                to: UIColor(red: 0.5, green: 0.3, blue: 0.3, alpha: 1)
            )
        }
    }

    private static func gradient(size: CGSize, from: UIColor, to: UIColor) -> Data {
        UIGraphicsImageRenderer(size: size).pngData { context in
            let colors = [from.cgColor, to.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
    }
}

private final class FakeServerStorage: SecureStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func data(for account: String) throws -> Data? {
        lock.withLock { values[account] }
    }

    func set(_ data: Data, for account: String) throws {
        lock.withLock { values[account] = data }
    }

    func remove(_ account: String) throws {
        lock.withLock { values[account] = nil }
    }
}
#endif
