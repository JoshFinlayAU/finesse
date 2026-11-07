import Foundation
import Observation
import OSLog
import TVServices
import UIKit

typealias JellyfinClientFactory = @Sendable (URL, DeviceIdentity) -> any JellyfinClient

/// Tells the Top Shelf who is signed in. Nil means nobody, which empties it.
protocol TopShelfPublishing: Sendable {
    func publish(_ shared: TopShelfSharedSession?)
}

struct NoTopShelf: TopShelfPublishing {
    func publish(_ shared: TopShelfSharedSession?) {}
}

struct KeychainTopShelf: TopShelfPublishing {
    private static let logger = Logger(subsystem: "Finesse", category: "TopShelf")

    func publish(_ shared: TopShelfSharedSession?) {
        do {
            if let shared {
                try TopShelfSessionStore.live.save(shared)
            } else {
                try TopShelfSessionStore.live.clear()
            }
        } catch {
            Self.logger.error("Could not update the Top Shelf session: \(String(describing: error))")
        }
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
}

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
    /// Changes each time a user becomes current, even the same user again.
    private(set) var activationCount = 0
    /// A link from the Top Shelf that the signed-in shell hasn't opened yet.
    private(set) var pendingLink: FinesseDeepLink?
    /// Why a link from the Top Shelf couldn't be opened.
    var linkError: String?

    let identity: DeviceIdentity
    let makeClient: JellyfinClientFactory
    private let store: SessionStore
    private let topShelf: any TopShelfPublishing
    private let logger = Logger(subsystem: "Finesse", category: "Accounts")
    /// The Keychain failed when read, so it may still hold other users. Saving would overwrite them.
    private var storeIsUnread = false

    init(
        store: SessionStore,
        identity: DeviceIdentity,
        makeClient: @escaping JellyfinClientFactory,
        topShelf: any TopShelfPublishing = NoTopShelf()
    ) {
        self.store = store
        self.identity = identity
        self.makeClient = makeClient
        self.topShelf = topShelf
    }

    static func live() -> AppModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-FinesseFakeServer") {
            return fakeServer()
        }
        #endif
        let storage = KeychainStorage(service: "Finesse")
        let store = SessionStore(storage: storage)
        #if DEBUG
        // UI tests that must start at the server step, whatever an earlier test left signed in.
        if ProcessInfo.processInfo.arguments.contains("-FinesseSignedOut") {
            try? store.removeAll()
        }
        #endif
        return AppModel(
            store: store,
            identity: DeviceIdentityStore(storage: storage).identity(deviceName: UIDevice.current.name),
            makeClient: { url, device in
                LiveJellyfinClient(serverURL: url, device: device, onWatchStateChanged: {
                    TVTopShelfContentProvider.topShelfContentDidChange()
                })
            },
            topShelf: KeychainTopShelf()
        )
    }

    /// Users holding a token on the given server, in the order they first signed in.
    func knownSessions(on serverURL: URL?) -> [UserSession] {
        guard let serverURL else { return [] }
        return accounts.sessions.filter { $0.serverURL == serverURL }
    }

    /// Restores the last user with no network call. An expired token surfaces on the first request.
    func restore() async {
        guard phase == .launching else { return }
        do {
            accounts = try store.load()
        } catch is DecodingError {
            // Nothing can ever read this data, so starting afresh loses nothing usable.
            logger.error("Stored accounts are unreadable, starting afresh")
        } catch {
            storeIsUnread = true
            logger.error("Could not read stored accounts: \(String(describing: error))")
        }
        guard let current = accounts.currentSession else {
            phase = .signedOut
            topShelf.publish(nil)
            await routePendingLink()
            return
        }
        await activate(current, using: makeClient(current.serverURL, identity))
        await routePendingLink()
    }

    /// A link from the Top Shelf. It can arrive before the restore has finished, and it can be for
    /// another user than the one signed in now, because the shelf may be older than a switch.
    func open(_ url: URL) async {
        guard let link = FinesseDeepLink(url: url) else {
            logger.notice("Ignored a link that isn't one of ours")
            return
        }
        pendingLink = link
        await routePendingLink()
    }

    /// The signed-in shell has dealt with it.
    func finishLink() {
        pendingLink = nil
    }

    private func routePendingLink() async {
        guard let link = pendingLink, phase != .launching, session?.accountKey != link.account else {
            return
        }
        if let target = accounts.sessions.first(where: { $0.accountKey == link.account }) {
            await switchUser(to: target)
        } else {
            pendingLink = nil
            linkError = "That belongs to a user who isn't signed in to Finesse here."
        }
    }

    /// Adopts a session that `client` has just signed in.
    func completeSignIn(_ session: UserSession, client: any JellyfinClient) async {
        accounts.upsert(session)
        save()
        await activate(session, using: client)
    }

    /// Switches to a user who already holds a token, with no password and no network call.
    func switchUser(to session: UserSession) async {
        let target = client.flatMap { $0.serverURL == session.serverURL ? $0 : nil }
            ?? makeClient(session.serverURL, identity)
        accounts.current = session.accountKey
        save()
        await activate(session, using: target)
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
        topShelf.publish(nil)
    }

    /// The client gets the session before any screen can use it, so a first request is never unauthenticated.
    private func activate(_ session: UserSession, using client: any JellyfinClient) async {
        await client.setSession(session)
        self.client = client
        self.session = session
        activationCount += 1
        phase = .signedIn
        topShelf.publish(TopShelfSharedSession(session: session, device: identity))
    }

    private func save() {
        do {
            if storeIsUnread {
                var stored = try store.load()
                stored.merge(accounts)
                accounts = stored
                storeIsUnread = false
            }
            try store.save(accounts)
        } catch {
            logger.error("Could not store accounts: \(String(describing: error))")
        }
    }
}
