import Foundation
import Testing
@testable import FinEsse

@MainActor
struct AppModelTests {
    @Test func startsSignedOutWithNoStoredAccounts() {
        let app = makeApp()
        app.restore()
        #expect(app.phase == .signedOut)
    }

    @Test func restoresTheLastUserAcrossLaunches() async {
        let storage = InMemoryStorage()
        let client = InMemoryJellyfinClient()
        let first = makeApp(client: client, storage: storage)
        first.restore()
        first.completeSignIn(.test(), client: client)

        let second = makeApp(client: client, storage: storage)
        second.restore()

        #expect(second.phase == .signedIn)
        #expect(second.session == .test())
        #expect(second.accounts.lastServerURL == UserSession.test().serverURL)
    }

    @Test func switchingNeedsNoPasswordAndChangesTheClientSession() async {
        let client = InMemoryJellyfinClient()
        let app = makeApp(client: client)
        app.restore()
        let alice = UserSession.test(user: "a", name: "Alice", token: "token-a")
        let bob = UserSession.test(user: "b", name: "Bob", token: "token-b")
        app.completeSignIn(alice, client: client)
        app.completeSignIn(bob, client: client)

        app.switchUser(to: alice)

        #expect(app.session == alice)
        #expect(app.accounts.currentSession == alice)
        #expect(app.knownSessions(on: alice.serverURL).count == 2)
        await waitForSession(alice, on: client)
    }

    @Test func signOutForgetsOnlyThatUserAndKeepsTheServer() async {
        let client = InMemoryJellyfinClient()
        let app = makeApp(client: client)
        app.restore()
        let alice = UserSession.test(user: "a", name: "Alice")
        let bob = UserSession.test(user: "b", name: "Bob")
        app.completeSignIn(alice, client: client)
        app.completeSignIn(bob, client: client)

        await app.signOut()

        #expect(app.phase == .signedOut)
        #expect(app.session == nil)
        #expect(app.knownSessions(on: alice.serverURL) == [alice])
        #expect(app.accounts.lastServerURL == alice.serverURL)
    }

    @Test func signOutForgetsTheUserEvenWhenTheServerIsUnreachable() async {
        let client = InMemoryJellyfinClient()
        await client.configure { $0.failure = .network("offline") }
        let app = makeApp(client: client)
        app.restore()
        app.completeSignIn(.test(), client: client)

        await app.signOut()

        #expect(app.phase == .signedOut)
        #expect(app.accounts.sessions.isEmpty)
    }

    @Test func expiredSessionReturnsToSignIn() {
        let client = InMemoryJellyfinClient()
        let app = makeApp(client: client)
        app.restore()
        app.completeSignIn(.test(), client: client)

        app.sessionExpired()

        #expect(app.phase == .signedOut)
        #expect(app.accounts.sessions.isEmpty)
    }

    private func waitForSession(_ session: UserSession, on client: InMemoryJellyfinClient) async {
        for _ in 0..<100 {
            if await client.currentSession() == session { return }
            await Task.yield()
        }
        Issue.record("Client never received the session")
    }
}
