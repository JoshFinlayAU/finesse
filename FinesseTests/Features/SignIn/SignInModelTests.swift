import Foundation
import Testing
@testable import FinEsse

@MainActor
struct SignInModelTests {
    private func connected(
        client: InMemoryJellyfinClient = InMemoryJellyfinClient(),
        app: AppModel? = nil
    ) async -> (SignInModel, AppModel) {
        let app = app ?? makeApp(client: client)
        app.restore()
        let model = SignInModel(app: app, quickConnectInterval: .milliseconds(1))
        model.serverAddress = "fake.invalid"
        await model.connect()
        return (model, app)
    }

    @Test func rejectsAnInvalidAddressWithoutCallingTheServer() async {
        let app = makeApp()
        let model = SignInModel(app: app)
        model.serverAddress = "ftp://nope"
        await model.connect()
        #expect(model.errorMessage != nil)
        #expect(model.path.isEmpty)
    }

    @Test func connectChecksTheServerAndListsUsers() async {
        let (model, _) = await connected()
        #expect(model.path == [.users])
        #expect(model.serverInfo?.name == "Fake Server")
        #expect(model.userChoices.map(\.name) == ["Test User"])
        #expect(model.quickConnectAvailable)
    }

    @Test func connectFailureStaysOnTheServerStep() async {
        let client = InMemoryJellyfinClient()
        await client.configure { $0.failure = .notAJellyfinServer }
        let (model, _) = await connected(client: client)
        #expect(model.path.isEmpty)
        #expect(model.errorMessage == JellyfinError.notAJellyfinServer.userMessage)
    }

    @Test func wrongPasswordShowsAnErrorAndStaysSignedOut() async {
        let (model, app) = await connected()
        await model.signIn(username: "Test User", password: "wrong")
        #expect(app.phase == .signedOut)
        #expect(model.errorMessage == JellyfinError.invalidCredentials.userMessage)
    }

    @Test func correctPasswordSignsIn() async {
        let (model, app) = await connected()
        await model.signIn(username: "Test User", password: "password")
        #expect(app.phase == .signedIn)
        #expect(app.session?.user.name == "Test User")
        #expect(app.accounts.sessions.count == 1)
    }

    @Test func userWithAPasswordAsksForIt() async {
        let (model, app) = await connected()
        await model.choose(model.userChoices[0])
        #expect(model.path.last == .password(username: "Test User"))
        #expect(app.phase == .signedOut)
    }

    @Test func userWithoutAPasswordSignsInDirectly() async {
        let client = InMemoryJellyfinClient()
        await client.configure {
            $0.publicUsersValue = [PublicUser(id: "o", name: "Open", hasPassword: false)]
            $0.credentials = ["Open": ""]
        }
        let (model, app) = await connected(client: client)
        await model.choose(model.userChoices[0])
        #expect(app.session?.user.name == "Open")
    }

    @Test func heldSessionIsListedFirstAndNeedsNoPassword() async {
        let client = InMemoryJellyfinClient()
        let held = UserSession.test(user: "hidden", name: "Hidden", server: URL(string: "http://fake.invalid:8096")!)
        let app = makeApp(client: client)
        app.restore()
        app.completeSignIn(held, client: client)
        await app.signOut()
        app.completeSignIn(held, client: client)

        let (model, _) = await connected(client: client, app: app)

        #expect(model.userChoices.map(\.name) == ["Hidden", "Test User"])
        await model.choose(model.userChoices[0])
        #expect(app.session == held)
    }

    @Test func quickConnectShowsTheCodeThenSignsIn() async {
        let client = InMemoryJellyfinClient()
        await client.configure { $0.quickConnectPollsUntilApproved = 2 }
        let (model, app) = await connected(client: client)
        await model.runQuickConnect()
        #expect(model.quickConnectCode == "123456")
        #expect(app.phase == .signedIn)
    }

    @Test func quickConnectFailureShowsAnError() async {
        let client = InMemoryJellyfinClient()
        await client.configure { $0.quickConnectEnabled = false }
        let (model, app) = await connected(client: client)
        await model.runQuickConnect()
        #expect(model.errorMessage == JellyfinError.quickConnectDisabled.userMessage)
        #expect(app.phase == .signedOut)
    }
}
