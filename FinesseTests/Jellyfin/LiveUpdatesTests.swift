import Foundation
import Testing
@testable import FinEsse

/// Messages as Jellyfin 12.4.0 sent them to the test user, with the IDs replaced.
private enum Recorded {
    static let user = "0a1b2c3d4e5f60718293a4b5c6d7e8f9"
    static let dashedUser = "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9"
    static let forceKeepAlive = #"{"MessageType":"ForceKeepAlive","Data":60,"MessageId":"m1"}"#
    static let keepAlive = #"{"MessageType":"KeepAlive","MessageId":"m2"}"#
    static let played = #"""
    {"MessageType":"UserDataChanged","Data":{"UserId":"0a1b2c3d4e5f60718293a4b5c6d7e8f9","UserDataList":[
    {"PlaybackPositionTicks":0,"PlayCount":1,"IsFavorite":false,"LastPlayedDate":"2026-11-09T02:10:00.000Z","Played":true,"Key":"k1","ItemId":"movie1"},
    {"PlaybackPositionTicks":12000000000,"PlayCount":0,"IsFavorite":true,"Played":false,"Key":"k2","ItemId":"folder1"}]},"MessageId":"m3"}
    """#
    static let libraryChanged = #"""
    {"MessageType":"LibraryChanged","Data":{"FoldersAddedTo":[],"FoldersRemovedFrom":[],"ItemsAdded":["ep1","ep2"],"ItemsRemoved":["old"],"ItemsUpdated":["show"],"CollectionFolders":["tv"],"IsEmpty":false},"MessageId":"m4"}
    """#
}

@Suite struct LiveMessageTests {
    @Test func keepAlives() {
        #expect(LiveMessage.parse(Recorded.forceKeepAlive, userID: Recorded.user) == .forceKeepAlive(seconds: 60))
        #expect(LiveMessage.parse(Recorded.keepAlive, userID: Recorded.user) == .keepAlive)
    }

    @Test func userDataForThisUser() {
        let expected = LiveMessage.event(.userDataChanged([
            UserDataChange(itemID: "movie1", isPlayed: true, playbackPosition: .zero, isFavorite: false),
            UserDataChange(itemID: "folder1", isPlayed: false, playbackPosition: Ticks(seconds: 1200), isFavorite: true),
        ]))
        #expect(LiveMessage.parse(Recorded.played, userID: Recorded.user) == expected)
        // The same user written with dashes and in capitals, as other parts of the API write IDs.
        #expect(LiveMessage.parse(Recorded.played, userID: Recorded.dashedUser.uppercased()) == expected)
    }

    @Test func userDataForSomeoneElseIsIgnored() {
        #expect(LiveMessage.parse(Recorded.played, userID: "someone-else") == .ignored)
    }

    @Test func libraryChanges() {
        #expect(LiveMessage.parse(Recorded.libraryChanged, userID: Recorded.user)
            == .event(.libraryChanged(LibraryChange(added: ["ep1", "ep2"], updated: ["show"], removed: ["old"]))))
        let foldersOnly = #"{"MessageType":"LibraryChanged","Data":{"FoldersAddedTo":["f"],"ItemsAdded":[],"ItemsRemoved":[],"ItemsUpdated":[]}}"#
        #expect(LiveMessage.parse(foldersOnly, userID: Recorded.user) == .event(.libraryChanged(LibraryChange())))
        let empty = #"{"MessageType":"LibraryChanged","Data":{"FoldersAddedTo":[],"ItemsAdded":[],"ItemsRemoved":[],"ItemsUpdated":[]}}"#
        #expect(LiveMessage.parse(empty, userID: Recorded.user) == .ignored)
    }

    @Test func anythingElseIsIgnored() {
        for text in [
            #"{"MessageType":"RefreshProgress","Data":{"ItemId":"x","Progress":"50"}}"#,
            #"{"MessageType":"Sessions","Data":[]}"#,
            #"{"MessageType":"ForceKeepAlive","Data":"soon"}"#,
            #"{"Data":1}"#,
            "not json",
            "",
        ] {
            #expect(LiveMessage.parse(text, userID: Recorded.user) == .ignored)
        }
    }

    @Test func everyListenerHearsEachEvent() async {
        let hub = ServerEventHub()
        var first = hub.stream().makeAsyncIterator()
        var second = hub.stream().makeAsyncIterator()
        #expect(hub.listenerCount == 2)
        hub.send(.catchUp)
        #expect(await first.next() == .catchUp)
        #expect(await second.next() == .catchUp)
    }

    @Test func theHeaderCarriesTheTokenAndTheURLDoesNot() async throws {
        let device = DeviceIdentity(clientName: "Finesse", clientVersion: "1.0", deviceName: "Lounge, TV", deviceID: "dev-1")
        let header = LiveJellyfinClient.authorization(device: device, token: "secret-token")
        #expect(header == #"MediaBrowser Client="Finesse", Device="Lounge TV", DeviceId="dev-1", Version="1.0", Token="secret-token""#)
    }
}

/// Records each wait, then waits only briefly, so reconnecting and the fallback can be checked quickly.
private actor Waits {
    private(set) var all: [Duration] = []
    func add(_ duration: Duration) { all.append(duration) }

    nonisolated func sleep() -> @Sendable (Duration) async throws -> Void {
        { duration in
            await self.add(duration)
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private func eventually(_ condition: () async -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
    for _ in 0..<300 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting", sourceLocation: sourceLocation)
}

/// Collects what the hub sends. Catch-ups are counted apart from the changes.
private actor Heard {
    private(set) var events: [ServerEvent] = []
    func add(_ event: ServerEvent) { events.append(event) }
    var changes: [ServerEvent] { events.filter { $0 != .catchUp } }
    var catchUps: Int { events.filter { $0 == .catchUp }.count }
}

private func listen(to hub: ServerEventHub) -> (Heard, Task<Void, Never>) {
    let heard = Heard()
    let stream = hub.stream()
    let task = Task {
        for await event in stream {
            await heard.add(event)
        }
    }
    return (heard, task)
}

@Suite struct LiveUpdatesTests {
    private func signedIn() async throws -> InMemoryJellyfinClient {
        let client = InMemoryJellyfinClient()
        _ = try await client.signIn(username: "Test User", password: "password")
        return client
    }

    @Test func connectsKeepsAliveAndPassesEventsOn() async throws {
        let client = try await signedIn()
        let waits = Waits()
        let live = LiveUpdates(source: client, fallbackInterval: .seconds(3600), sleep: waits.sleep())
        let (heard, listening) = listen(to: live.events)
        defer { listening.cancel() }
        await live.start()
        await eventually { await live.isConnected }
        // Answers the server's ForceKeepAlive straight away, then every half of its 60 seconds.
        await eventually { await client.liveMessagesSent.count >= 2 }
        #expect(await client.liveMessagesSent.allSatisfy { $0 == LiveMessage.keepAliveText })
        #expect(await waits.all.contains(.seconds(30)))

        let userID = try #require(await client.currentSession()?.user.id)
        await client.emit(#"{"MessageType":"UserDataChanged","Data":{"UserId":"\#(userID)","UserDataList":[{"ItemId":"a","Played":true,"PlaybackPositionTicks":0,"IsFavorite":false}]}}"#)
        await client.emit(#"{"MessageType":"UserDataChanged","Data":{"UserId":"someone-else","UserDataList":[{"ItemId":"b","Played":true}]}}"#)
        await client.emit(#"{"MessageType":"LibraryChanged","Data":{"ItemsAdded":["new"],"ItemsUpdated":[],"ItemsRemoved":[]}}"#)
        await eventually { await heard.changes.count == 2 }
        #expect(await heard.changes == [
            .userDataChanged([UserDataChange(itemID: "a", isPlayed: true, playbackPosition: .zero, isFavorite: false)]),
            .libraryChanged(LibraryChange(added: ["new"])),
        ])
        await live.stop()
        #expect(await client.openLiveSocketCount == 0)
    }

    @Test func reconnectsAfterADropAndCatchesUp() async throws {
        let client = try await signedIn()
        let live = LiveUpdates(source: client, fallbackInterval: .seconds(3600), sleep: Waits().sleep())
        let (heard, listening) = listen(to: live.events)
        defer { listening.cancel() }
        await live.start()
        await eventually { await live.isConnected }
        #expect(await heard.catchUps == 0)

        await client.dropLiveConnections()
        await eventually { await client.liveSocketsOpened == 2 }
        await eventually { await live.isConnected }
        // The server doesn't replay what it sent while the connection was down.
        await eventually { await heard.catchUps == 1 }
        await live.stop()
    }

    @Test func backsOffWhileTheServerIsDown() async throws {
        let client = try await signedIn()
        await client.configure { $0.liveSocketFailure = .network("down") }
        let waits = Waits()
        let live = LiveUpdates(source: client, fallbackInterval: .seconds(3600), sleep: waits.sleep())
        await live.start()
        await eventually { await waits.all.filter { $0 != .seconds(3600) }.count >= 8 }
        await live.stop()
        let retries = await waits.all.filter { $0 != .seconds(3600) }
        #expect(Array(retries.prefix(8)) == [1, 2, 4, 8, 16, 32, 60, 60].map { Duration.seconds($0) })
        #expect(LiveUpdates.backoff(afterFailures: 40) == .seconds(60))
    }

    @Test func pausesInTheBackgroundAndCatchesUpOnReturn() async throws {
        let client = try await signedIn()
        let live = LiveUpdates(source: client, fallbackInterval: .seconds(3600), sleep: Waits().sleep())
        let (heard, listening) = listen(to: live.events)
        defer { listening.cancel() }
        await live.start()
        await eventually { await live.isConnected }

        await live.pause()
        #expect(await client.openLiveSocketCount == 0)
        #expect(await !live.isConnected)

        await live.resume()
        await eventually { await heard.catchUps == 1 }
        await eventually { await live.isConnected }
        #expect(await client.liveSocketsOpened == 2)
        await live.stop()
    }

    @Test func stopIsFinal() async throws {
        let client = try await signedIn()
        let live = LiveUpdates(source: client, sleep: Waits().sleep())
        await live.start()
        await eventually { await live.isConnected }
        await live.stop()
        await live.resume()
        await live.start()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await client.liveSocketsOpened == 1)
        #expect(await client.openLiveSocketCount == 0)
    }

    @Test func withoutAConnectionTheFallbackCatchesUpNowAndThen() async throws {
        let waits = Waits()
        let live = LiveUpdates(source: nil, fallbackInterval: .seconds(300), sleep: waits.sleep())
        let (heard, listening) = listen(to: live.events)
        defer { listening.cancel() }
        await live.start()
        await eventually { await heard.catchUps >= 2 }
        await live.stop()
        // Never more often than every five minutes.
        #expect(await waits.all.allSatisfy { $0 == .seconds(300) })
    }

    @Test func theFallbackStaysQuietWhileConnected() async throws {
        let client = try await signedIn()
        let live = LiveUpdates(source: client, fallbackInterval: .milliseconds(1), sleep: Waits().sleep())
        let (heard, listening) = listen(to: live.events)
        defer { listening.cancel() }
        await live.start()
        await eventually { await live.isConnected }
        let before = await heard.catchUps
        try await Task.sleep(for: .milliseconds(200))
        #expect(await heard.catchUps == before)
        await live.stop()
    }

    @Test func aNewEpisodeOnTheFakeServerIsAnnounced() async throws {
        let client = try await signedIn()
        var show = MediaItem(id: "show", name: "Show", kind: .series)
        show.userState.unplayedItemCount = 2
        let seeded = show
        await client.configure { $0.allItems = [seeded] }
        let live = LiveUpdates(source: client, fallbackInterval: .seconds(3600), sleep: Waits().sleep())
        let (heard, listening) = listen(to: live.events)
        defer { listening.cancel() }
        await live.start()
        await eventually { await live.isConnected }
        var episode = MediaItem(id: "ep", name: "New", kind: .episode)
        episode.seriesID = "show"
        await client.addEpisode(episode)
        await eventually { await heard.changes.count == 1 }
        #expect(await heard.changes == [.libraryChanged(LibraryChange(added: ["ep"], updated: ["show"]))])
        #expect(try await client.item(id: "show").userState.unplayedItemCount == 3)
        await live.stop()
    }
}

@MainActor
@Suite struct RefreshDebouncerTests {
    @Test func aBurstMakesOneRefresh() async throws {
        var refreshes = 0
        let debouncer = RefreshDebouncer(quiet: .milliseconds(80), longest: .seconds(5)) { refreshes += 1 }
        for _ in 0..<10 {
            debouncer.signal()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(refreshes == 0)
        try await Task.sleep(for: .milliseconds(300))
        #expect(refreshes == 1)

        debouncer.signal()
        try await Task.sleep(for: .milliseconds(300))
        #expect(refreshes == 2)
    }

    @Test func aLongBurstStillRefreshesInTime() async throws {
        var refreshes = 0
        let debouncer = RefreshDebouncer(quiet: .milliseconds(100), longest: .milliseconds(250)) { refreshes += 1 }
        // Changes every 40 ms never go quiet, so only the longest wait lets one through.
        for _ in 0..<12 {
            debouncer.signal()
            try await Task.sleep(for: .milliseconds(40))
        }
        #expect(refreshes >= 1)
        debouncer.cancel()
    }

    @Test func cancellingDropsWhatIsWaiting() async throws {
        var refreshes = 0
        let debouncer = RefreshDebouncer(quiet: .milliseconds(50), longest: .seconds(1)) { refreshes += 1 }
        debouncer.signal()
        debouncer.cancel()
        try await Task.sleep(for: .milliseconds(200))
        #expect(refreshes == 0)
    }
}
