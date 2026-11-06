import Foundation
import TVServices
import Testing
@testable import FinEsse

@Suite struct FinesseDeepLinkTests {
    @Test func aLinkSurvivesTheTripThroughItsURL() throws {
        for action in [FinesseDeepLink.Action.play, .detail] {
            let link = FinesseDeepLink(action: action, itemID: "item 1", account: "server/user+1")
            let url = try #require(link.url)
            #expect(url.scheme == "finesse")
            #expect(FinesseDeepLink(url: url) == link)
        }
    }

    @Test(arguments: [
        "https://server/play?item=1&account=a",
        "finesse://other?item=1&account=a",
        "finesse://play?account=a",
        "finesse://play?item=1",
        "finesse://play?item=&account=a",
        "finesse://play",
    ])
    func aMalformedLinkIsIgnored(text: String) throws {
        #expect(FinesseDeepLink(url: try #require(URL(string: text))) == nil)
    }
}

@Suite struct TopShelfContentTests {
    private let account = "server/user"

    private func client(
        resume: [MediaItem] = [],
        nextUp: [MediaItem] = [],
        latest: [MediaItem] = []
    ) async throws -> InMemoryJellyfinClient {
        let client = InMemoryJellyfinClient()
        _ = try await client.signIn(username: "Test User", password: "password")
        await client.configure {
            $0.resumeValue = resume
            $0.nextUpValue = nextUp
            $0.latestValue = latest
        }
        return client
    }

    private func item(_ id: String, kind: ItemKind = .movie) -> MediaItem {
        MediaItem(id: id, name: "Title \(id)", kind: kind)
    }

    @Test func theThreeRowsComeInOrder() async throws {
        let client = try await client(resume: [item("1")], nextUp: [item("2")], latest: [item("3")])
        let sections = try #require(await TopShelfContent.sections(client: client, account: account))
        #expect(sections.map(\.title) == ["Continue Watching", "Next Up", "Recently Added"])
        #expect(sections.map { $0.entries.map(\.id) } == [["1"], ["2"], ["3"]])
    }

    @Test func anEmptyRowIsLeftOut() async throws {
        let client = try await client(latest: [item("3")])
        let sections = try #require(await TopShelfContent.sections(client: client, account: account))
        #expect(sections.map(\.title) == ["Recently Added"])
    }

    @Test func aTitleShowsInOnlyTheFirstRowThatHasIt() async throws {
        let client = try await client(resume: [item("1")], nextUp: [item("1"), item("2")], latest: [item("2")])
        let sections = try #require(await TopShelfContent.sections(client: client, account: account))
        #expect(sections.map { $0.entries.map(\.id) } == [["1"], ["2"]])
    }

    @Test func nothingToShowGivesTheStaticImage() async throws {
        let client = try await client()
        #expect(await TopShelfContent.sections(client: client, account: account) == nil)
    }

    @Test func aRefusedTokenGivesTheStaticImageWhateverElseWorked() async throws {
        let client = try await client(latest: [item("3")])
        await client.configure { $0.failure = .notSignedIn }
        #expect(await TopShelfContent.sections(client: client, account: account) == nil)
    }

    @Test func anOfflineServerGivesTheStaticImage() async throws {
        let client = try await client(latest: [item("3")])
        await client.configure { $0.failure = .network("Offline") }
        #expect(await TopShelfContent.sections(client: client, account: account) == nil)
    }

    @Test func noSessionGivesTheStaticImage() async throws {
        let store = TopShelfSessionStore(storage: InMemoryStorage())
        #expect(try store.load() == nil)
    }

    @Test func progressComesThroughOnlyForAPartWatchedItem() async throws {
        var started = item("1")
        started.runTime = Ticks(seconds: 1000)
        started.userState.playbackPosition = Ticks(seconds: 250)
        let client = try await client(resume: [started], nextUp: [item("2")])
        let sections = try #require(await TopShelfContent.sections(client: client, account: account))
        #expect(sections[0].entries[0].progress == 0.25)
        #expect(sections[1].entries[0].progress == nil)
    }

    @Test func eachLinkNamesTheItemAndTheUser() async throws {
        let client = try await client(latest: [item("3")])
        let entry = try #require(await TopShelfContent.sections(client: client, account: account)?.first?.entries.first)
        #expect(entry.playLink == FinesseDeepLink(action: .play, itemID: "3", account: account))
        #expect(entry.displayLink == FinesseDeepLink(action: .detail, itemID: "3", account: account))
    }

    /// The system holds these URLs and loads the images itself.
    @Test func noURLHoldsTheToken() async throws {
        let live = LiveJellyfinClient(
            serverURL: try #require(URL(string: "http://server.invalid:8096")),
            device: DeviceIdentity(clientName: "c", clientVersion: "1", deviceName: "d", deviceID: "device")
        )
        let token = "SECRET-TOKEN"
        await live.setSession(UserSession(
            serverURL: live.serverURL, serverID: "server", user: User(id: "user", name: "n"), accessToken: token
        ))
        var movie = item("1")
        movie.images.primaryTag = "tag"
        #expect(live.posterURL(for: movie)?.absoluteString.contains(token) == false)
        #expect(live.landscapeURL(for: movie)?.absoluteString.contains(token) == false)
        #expect(FinesseDeepLink(action: .play, itemID: "1", account: "server/user").url?.absoluteString.contains(token) == false)
    }

    @Test func anEpisodeNamesItsSeriesAndNumber() async throws {
        var episode = item("1", kind: .episode)
        episode.seriesName = "A Show"
        episode.parentIndexNumber = 2
        episode.indexNumber = 5
        let client = try await client(nextUp: [episode])
        let entry = try #require(await TopShelfContent.sections(client: client, account: account)?.first?.entries.first)
        #expect(entry.title.hasPrefix("A Show S2 E5"))
    }

    @Test func whatTheSystemGetsMatchesTheRows() throws {
        let link = FinesseDeepLink(action: .play, itemID: "1", account: account)
        let detail = FinesseDeepLink(action: .detail, itemID: "1", account: account)
        let entry = TopShelfEntry(
            id: "1",
            title: "One",
            imageURL: URL(string: "http://server.invalid/image"),
            shape: .landscape,
            progress: 0.5,
            playLink: link,
            displayLink: detail
        )
        let shelf = TopShelfContent.shelf([TopShelfSection(title: "Next Up", entries: [entry])])
        let section = try #require(shelf.sections.first)
        #expect(section.title == "Next Up")
        let item = try #require(section.items.first)
        #expect(item.title == "One")
        #expect(item.imageShape == .hdtv)
        #expect(item.playbackProgress == 0.5)
        #expect(item.playAction?.url == link.url)
        #expect(item.displayAction?.url == detail.url)
        #expect(item.imageURL(for: .screenScale2x) == entry.imageURL)
    }
}

@MainActor
@Suite struct TopShelfPublishingTests {
    private final class Recorder: TopShelfPublishing, @unchecked Sendable {
        var published: [TopShelfSharedSession?] = []
        func publish(_ shared: TopShelfSharedSession?) {
            published.append(shared)
        }
    }

    private func app(storage: InMemoryStorage = InMemoryStorage(), client: InMemoryJellyfinClient, recorder: Recorder) -> AppModel {
        AppModel(
            store: SessionStore(storage: storage),
            identity: DeviceIdentity(clientName: "c", clientVersion: "1", deviceName: "d", deviceID: "device"),
            makeClient: { _, _ in client },
            topShelf: recorder
        )
    }

    @Test func theShelfFollowsSignInSwitchAndSignOut() async throws {
        let client = InMemoryJellyfinClient()
        let recorder = Recorder()
        let app = app(client: client, recorder: recorder)
        await app.restore()
        #expect(recorder.published.count == 1)
        #expect(recorder.published[0] == nil, "Nobody is signed in")

        let alice = UserSession.test(user: "a", name: "Alice", token: "token-a")
        let bob = UserSession.test(user: "b", name: "Bob", token: "token-b")
        await app.completeSignIn(alice, client: client)
        #expect(recorder.published.last??.session == alice)
        await app.completeSignIn(bob, client: client)
        #expect(recorder.published.last??.session == bob)
        await app.switchUser(to: alice)
        #expect(recorder.published.last??.session == alice)
        #expect(recorder.published.last??.device.deviceID == "device")

        await app.signOut()
        #expect(recorder.published.last == .some(nil))
    }

    @Test func anExpiredSessionEmptiesTheShelf() async {
        let client = InMemoryJellyfinClient()
        let recorder = Recorder()
        let app = app(client: client, recorder: recorder)
        await app.restore()
        await app.completeSignIn(.test(), client: client)
        app.sessionExpired()
        #expect(recorder.published.last == .some(nil))
    }

    /// The owner's TV already has a stored account from before this existed.
    @Test func restoringAnExistingUserPublishesThem() async {
        let storage = InMemoryStorage()
        let client = InMemoryJellyfinClient()
        let first = app(storage: storage, client: client, recorder: Recorder())
        await first.restore()
        await first.completeSignIn(.test(), client: client)

        let recorder = Recorder()
        let second = app(storage: storage, client: client, recorder: recorder)
        await second.restore()
        #expect(recorder.published.last??.session == .test())
    }

    @Test func theSharedStoreHoldsOnlyTheActiveUser() throws {
        let storage = InMemoryStorage()
        let store = TopShelfSessionStore(storage: storage)
        let device = DeviceIdentity(clientName: "c", clientVersion: "1", deviceName: "d", deviceID: "device")
        try store.save(TopShelfSharedSession(session: .test(user: "a", name: "A", token: "a"), device: device))
        try store.save(TopShelfSharedSession(session: .test(user: "b", name: "B", token: "b"), device: device))
        #expect(try store.load()?.session.user.id == "b")
        try store.clear()
        #expect(try store.load() == nil)
    }
}

@MainActor
@Suite struct DeepLinkRoutingTests {
    private let alice = UserSession.test(user: "a", name: "Alice", token: "token-a")
    private let bob = UserSession.test(user: "b", name: "Bob", token: "token-b")

    private func app(client: InMemoryJellyfinClient, storage: InMemoryStorage = InMemoryStorage()) -> AppModel {
        AppModel(
            store: SessionStore(storage: storage),
            identity: DeviceIdentity(clientName: "c", clientVersion: "1", deviceName: "d", deviceID: "device"),
            makeClient: { _, _ in client }
        )
    }

    private func url(_ action: FinesseDeepLink.Action, _ account: String, item: String = "1") -> URL {
        FinesseDeepLink(action: action, itemID: item, account: account).url!
    }

    @Test func aColdStartLinkWaitsForTheRestoreThenStays() async {
        let storage = InMemoryStorage()
        let client = InMemoryJellyfinClient()
        let first = app(client: client, storage: storage)
        await first.restore()
        await first.completeSignIn(alice, client: client)

        let second = app(client: client, storage: storage)
        await second.open(url(.play, alice.accountKey))
        #expect(second.pendingLink != nil, "It waits while launching")
        #expect(second.phase == .launching)
        await second.restore()
        #expect(second.session == alice)
        #expect(second.pendingLink?.account == alice.accountKey)
    }

    @Test func aColdStartLinkForAnotherKnownUserSwitchesToThem() async {
        let storage = InMemoryStorage()
        let client = InMemoryJellyfinClient()
        let first = app(client: client, storage: storage)
        await first.restore()
        await first.completeSignIn(alice, client: client)
        await first.completeSignIn(bob, client: client)

        let second = app(client: client, storage: storage)
        await second.open(url(.detail, alice.accountKey))
        await second.restore()
        #expect(second.session == alice)
        #expect(second.pendingLink != nil)
    }

    @Test func whileRunningALinkForAnotherKnownUserSwitches() async {
        let client = InMemoryJellyfinClient()
        let app = app(client: client)
        await app.restore()
        await app.completeSignIn(alice, client: client)
        await app.completeSignIn(bob, client: client)
        await app.open(url(.play, alice.accountKey))
        #expect(app.session == alice)
        #expect(app.pendingLink?.account == alice.accountKey)
    }

    @Test func aLinkForAnUnknownUserChangesNothingAndSaysSo() async {
        let client = InMemoryJellyfinClient()
        let app = app(client: client)
        await app.restore()
        await app.completeSignIn(alice, client: client)
        await app.open(url(.play, "server/stranger"))
        #expect(app.session == alice)
        #expect(app.pendingLink == nil)
        #expect(app.linkError != nil)
    }

    @Test func aLinkWhenSignedOutSaysSo() async {
        let client = InMemoryJellyfinClient()
        let app = app(client: client)
        await app.restore()
        await app.open(url(.play, alice.accountKey))
        #expect(app.phase == .signedOut)
        #expect(app.pendingLink == nil)
        #expect(app.linkError != nil)
    }

    @Test func aLinkThatIsNotOursIsIgnored() async throws {
        let client = InMemoryJellyfinClient()
        let app = app(client: client)
        await app.restore()
        await app.open(try #require(URL(string: "finesse://elsewhere")))
        #expect(app.pendingLink == nil)
        #expect(app.linkError == nil)
    }

    private func signedInClient(items: [MediaItem]) async throws -> InMemoryJellyfinClient {
        let client = InMemoryJellyfinClient()
        _ = try await client.signIn(username: "Test User", password: "password")
        await client.configure { $0.allItems = items }
        return client
    }

    private func movie(position: Double = 0) -> MediaItem {
        var movie = MediaItem(id: "1", name: "One", kind: .movie)
        movie.runTime = Ticks(seconds: 1000)
        movie.userState.playbackPosition = Ticks(seconds: position)
        return movie
    }

    @Test func playGoesToThePlayerAtTheServersPosition() async throws {
        let client = try await signedInClient(items: [movie(position: 300)])
        let navigator = AppNavigator()
        try await navigator.open(FinesseDeepLink(action: .play, itemID: "1", account: "a"), client: client)
        #expect(navigator.activePlayback?.item.id == "1")
        #expect(navigator.activePlayback?.resumePosition == Ticks(seconds: 300))
    }

    @Test func displayGoesToDetailOverAnythingPlaying() async throws {
        let client = try await signedInClient(items: [movie()])
        let navigator = AppNavigator()
        navigator.selectedTab = .movies
        navigator.play(MediaItem(id: "other", name: "Other", kind: .movie))
        try await navigator.open(FinesseDeepLink(action: .detail, itemID: "1", account: "a"), client: client)
        #expect(navigator.activePlayback == nil)
        #expect(navigator.selectedTab == .home)
        #expect(navigator.paths[.home]?.count == 1)
    }

    @Test func playOnWhatIsAlreadyPlayingLeavesItAlone() async throws {
        let client = try await signedInClient(items: [movie(position: 300)])
        let navigator = AppNavigator()
        navigator.play(movie(position: 300), resumeFrom: Ticks(seconds: 300))
        let running = navigator.activePlayback?.id
        try await navigator.open(FinesseDeepLink(action: .play, itemID: "1", account: "a"), client: client)
        #expect(navigator.activePlayback?.id == running)
    }

    @Test func playOnSomethingThatCannotPlayOpensItsDetail() async throws {
        let series = MediaItem(id: "1", name: "A Show", kind: .series)
        let client = try await signedInClient(items: [series])
        let navigator = AppNavigator()
        try await navigator.open(FinesseDeepLink(action: .play, itemID: "1", account: "a"), client: client)
        #expect(navigator.activePlayback == nil)
        #expect(navigator.paths[.home]?.count == 1)
    }

    @Test func anItemThatIsGoneThrowsAndChangesNothing() async throws {
        let client = try await signedInClient(items: [])
        let navigator = AppNavigator()
        navigator.selectedTab = .movies
        await #expect(throws: JellyfinError.notFound) {
            try await navigator.open(FinesseDeepLink(action: .play, itemID: "gone", account: "a"), client: client)
        }
        #expect(navigator.activePlayback == nil)
        #expect(navigator.selectedTab == .movies)
    }
}
