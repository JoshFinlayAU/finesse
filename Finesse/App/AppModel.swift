import Foundation
import Observation
import OSLog
import UIKit

typealias JellyfinClientFactory = @Sendable (URL, DeviceIdentity) -> any JellyfinClient

/// Owns who is signed in. Everything else reads the current client and session from here.
@Observable
@MainActor
final class AppModel {
    enum Phase: Equatable {
        case launching
        case signedOut
        case signedIn
    }

    private(set) var phase = Phase.launching
    private(set) var client: (any JellyfinClient)?
    private(set) var session: UserSession?
    private(set) var accounts = StoredAccounts()
    /// Changes each time the signed-out screen should start afresh.
    private(set) var signInAttempt = 0

    let identity: DeviceIdentity
    let makeClient: JellyfinClientFactory
    private let store: SessionStore
    private let logger = Logger(subsystem: "Finesse", category: "Accounts")

    init(store: SessionStore, identity: DeviceIdentity, makeClient: @escaping JellyfinClientFactory) {
        self.store = store
        self.identity = identity
        self.makeClient = makeClient
    }

    static func live() -> AppModel {
        let storage = KeychainStorage(service: "Finesse")
        return AppModel(
            store: SessionStore(storage: storage),
            identity: DeviceIdentityStore(storage: storage).identity(deviceName: UIDevice.current.name),
            // Interim until agent-2's live client lands: replace with the live client's initialiser.
            makeClient: { url, _ in InMemoryJellyfinClient(serverURL: url) }
        )
    }

    /// Users holding a token on the given server, in the order they first signed in.
    func knownSessions(on serverURL: URL?) -> [UserSession] {
        guard let serverURL else { return [] }
        return accounts.sessions.filter { $0.serverURL == serverURL }
    }

    /// Restores the last user with no network call. An expired token surfaces on the first request.
    func restore() {
        guard phase == .launching else { return }
        do {
            accounts = try store.load()
        } catch {
            logger.error("Could not read stored accounts: \(String(describing: error))")
        }
        guard let current = accounts.currentSession else {
            phase = .signedOut
            return
        }
        activate(current, using: makeClient(current.serverURL, identity))
    }

    /// Adopts a session that `client` has just signed in.
    func completeSignIn(_ session: UserSession, client: any JellyfinClient) {
        accounts.upsert(session)
        save()
        activate(session, using: client)
    }

    /// Switches to a user who already holds a token, with no password and no network call.
    func switchUser(to session: UserSession) {
        let target = client.flatMap { $0.serverURL == session.serverURL ? $0 : nil }
            ?? makeClient(session.serverURL, identity)
        accounts.current = session.accountKey
        save()
        activate(session, using: target)
    }

    /// Revokes the token where possible. The account is forgotten here even if the server is unreachable.
    func signOut() async {
        guard let client, let session else { return }
        do {
            try await client.signOut()
        } catch {
            logger.notice("Sign-out did not reach the server: \(String(describing: error))")
        }
        forget(session)
    }

    /// The server refused the stored token, so this user has to sign in again.
    func sessionExpired() {
        guard let session else { return }
        forget(session)
    }

    private func forget(_ session: UserSession) {
        accounts.remove(session)
        save()
        self.session = nil
        client = nil
        signInAttempt += 1
        phase = .signedOut
    }

    private func activate(_ session: UserSession, using client: any JellyfinClient) {
        self.client = client
        self.session = session
        phase = .signedIn
        Task { await client.setSession(session) }
    }

    private func save() {
        do {
            try store.save(accounts)
        } catch {
            logger.error("Could not store accounts: \(String(describing: error))")
        }
    }
}
