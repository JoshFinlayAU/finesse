import Foundation
import Testing
@testable import FinEsse

@MainActor
struct AppModelTests {
    @Test func startsSignedOutWithNoStoredAccounts() async {
        let app = makeApp()
        await app.restore()
        #expect(app.phase == .signedOut)
    }

    @Test func restoresTheLastUserAcrossLaunches() async {
        let storage = InMemoryStorage()
        let client = InMemoryJellyfinClient()
        let first = makeApp(client: client, storage: storage)
        await first.restore()
        await first.completeSignIn(.test(), client: client)

        let second = makeApp(client: client, storage: storage)
        await second.restore()

        #expect(second.phase == .signedIn)
        #expect(second.session == .test())
        #expect(second.accounts.lastServerURL == UserSession.test().serverURL)
    }

    @Test func switchingNeedsNoPasswordAndChangesTheClientSession() async {
        let client = InMemoryJellyfinClient()
        let app = makeApp(client: client)
        await app.restore()
        let alice = UserSession.test(user: "a", name: "Alice", token: "token-a")
        let bob = UserSession.test(user: "b", name: "Bob", token: "token-b")
        await app.completeSignIn(alice, client: client)
        await app.completeSignIn(bob, client: client)

        await app.switchUser(to: alice)

        #expect(app.session == alice)
        #expect(app.accounts.currentSession == alice)
        #expect(app.knownSessions(on: alice.serverURL).count == 2)
        #expect(await client.currentSession() == alice)
    }

    @Test func theClientHasTheSessionBeforeTheAppReportsSignedIn() async {
        let storage = InMemoryStorage()
        let client = InMemoryJellyfinClient()
        let first = makeApp(client: client, storage: storage)
        await first.restore()
        await first.completeSignIn(.test(), client: client)
        await client.setSession(nil)

        let second = makeApp(client: client, storage: storage)
        await second.restore()

        #expect(second.phase == .signedIn)
        #expect(await client.currentSession() == .test())
    }

    @Test func choosingTheCurrentUserAgainStillCountsAsAnActivation() async {
        let client = InMemoryJellyfinClient()
        let app = makeApp(client: client)
        await app.restore()
        await app.completeSignIn(.test(), client: client)
        let before = app.activationCount

        await app.switchUser(to: .test())

        #expect(app.activationCount == before + 1)
    }

    @Test func signOutForgetsOnlyThatUserAndKeepsTheServer() async {
        let client = InMemoryJellyfinClient()
        let app = makeApp(client: client)
        await app.restore()
        let alice = UserSession.test(user: "a", name: "Alice")
        let bob = UserSession.test(user: "b", name: "Bob")
        await app.completeSignIn(alice, client: client)
        await app.completeSignIn(bob, client: client)

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
        await app.restore()
        await app.completeSignIn(.test(), client: client)

        await app.signOut()

        #expect(app.phase == .signedOut)
        #expect(app.accounts.sessions.isEmpty)
    }

    @Test func expiredSessionReturnsToSignIn() async {
        let client = InMemoryJellyfinClient()
        let app = makeApp(client: client)
        await app.restore()
        await app.completeSignIn(.test(), client: client)

        app.sessionExpired()

        #expect(app.phase == .signedOut)
        #expect(app.accounts.sessions.isEmpty)
    }
}
