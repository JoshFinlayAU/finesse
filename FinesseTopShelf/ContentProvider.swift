import Foundation
import TVServices

/// Draws the shelf when Finesse is focused on the Home Screen. Returning nil shows the static image
/// from the app's asset catalog, which covers no session, an offline server and a refused token.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping ((any TVTopShelfContent)?) -> Void) {
        // The system calls this once and doesn't touch the handler again, so handing it over is safe.
        nonisolated(unsafe) let completion = completionHandler
        Task {
            let sections = await Self.loadSections()
            completion(sections.map(TopShelfContent.shelf))
        }
    }

    private static func loadSections() async -> [TopShelfSection]? {
        LiveJellyfinClient.keepSharedResponsesOffDisk()
        guard let shared = try? TopShelfSessionStore.live.load() else {
            return nil
        }
        let client = LiveJellyfinClient(
            serverURL: shared.session.serverURL,
            device: shared.device,
            makeSessionConfiguration: sessionConfiguration
        )
        await client.setSession(shared.session)
        return await TopShelfContent.sections(client: client, account: shared.session.accountKey)
    }

    /// The same no-disk rule as the app, and quick to give up because the system is waiting on this.
    @Sendable
    private static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = LiveJellyfinClient.sessionConfiguration()
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        return configuration
    }
}
