import Foundation
import Testing
@testable import FinEsse

/// Requests carry the password when signing in and the access token on every other call, so nothing
/// from the client's session may reach disk. The real proof is a scan of a simulator's app data.
@Suite struct SessionPersistenceTests {
    @Test func theLiveClientsSessionHasNoCache() {
        let configuration = LiveJellyfinClient.sessionConfiguration()
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func theLiveClientsSessionKeepsNoCookiesOrCredentialsOnDisk() {
        let configuration = LiveJellyfinClient.sessionConfiguration()
        // Ephemeral storage is private to the session and never written out.
        #expect(configuration.httpCookieStorage !== HTTPCookieStorage.shared)
        #expect(configuration.urlCredentialStorage !== URLCredentialStorage.shared)
    }

    @Test func theSDKKeepsTheConfigurationItIsGiven() throws {
        // A real session built from it can't fall back to the shared cache.
        let session = URLSession(configuration: LiveJellyfinClient.sessionConfiguration())
        #expect(session.configuration.urlCache == nil)
        session.invalidateAndCancel()
    }
}
