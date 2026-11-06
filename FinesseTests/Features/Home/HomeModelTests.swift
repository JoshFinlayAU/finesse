import Foundation
import Testing
@testable import FinEsse

private func signedInClient() async -> InMemoryJellyfinClient {
    let client = InMemoryJellyfinClient()
    await client.setSession(.test())
    return client
}

@MainActor
struct HomeModelTests {
    @Test func hubsAreInTheAgreedOrder() async {
        let client = await signedInClient()
        await client.configure {
            $0.latestValue = [.test("latest")]
            $0.nextUpValue = [.test("next", kind: .episode)]
            $0.resumeValue = [.test("resume", position: Ticks(seconds: 60))]
        }
        let model = HomeModel(client: client)
        await model.load()
        guard case .loaded(let hubs) = model.state else {
            Issue.record("Expected hubs, got \(model.state)")
            return
        }
        #expect(hubs.map(\.kind) == [.continueWatching, .nextUp, .recentlyAdded])
    }

    @Test func emptyRowsAreHidden() async {
        let client = await signedInClient()
        await client.configure { $0.latestValue = [.test("latest")] }
        let model = HomeModel(client: client)
        await model.load()
        guard case .loaded(let hubs) = model.state else {
            Issue.record("Expected hubs, got \(model.state)")
            return
        }
        #expect(hubs.map(\.kind) == [.recentlyAdded])
    }

    @Test func nothingToShowLoadsNoHubs() async {
        let model = HomeModel(client: await signedInClient())
        await model.load()
        #expect(model.state == .loaded([]))
    }

    @Test func totalFailureShowsAnErrorAndRetryRecovers() async {
        let client = await signedInClient()
        await client.configure { $0.failure = .network("offline") }
        let model = HomeModel(client: client)
        await model.load()
        #expect(model.state == .failed(JellyfinError.network("offline").userMessage))

        await client.configure {
            $0.failure = nil
            $0.latestValue = [.test("latest")]
        }
        await model.load()
        guard case .loaded(let hubs) = model.state else {
            Issue.record("Expected hubs, got \(model.state)")
            return
        }
        #expect(hubs.count == 1)
    }

    @Test func failedRefreshKeepsWhatIsShowing() async {
        let client = await signedInClient()
        await client.configure { $0.latestValue = [.test("latest")] }
        let model = HomeModel(client: client)
        await model.load()
        let before = model.state

        await client.configure { $0.failure = .network("offline") }
        await model.load()

        #expect(model.state == before)
    }

    @Test func refusedTokenIsReportedAsExpired() async {
        let client = InMemoryJellyfinClient()
        let model = HomeModel(client: client)
        await model.load()
        #expect(model.sessionExpired)
    }
}

struct MediaItemDisplayTests {
    @Test func episodeCardsLeadWithTheSeries() {
        var item = MediaItem.test("1", kind: .episode)
        item.seriesName = "Show"
        item.name = "Pilot"
        item.parentIndexNumber = 1
        item.indexNumber = 2
        #expect(item.cardTitle == "Show")
        #expect(item.cardSubtitle == "S1 E2 · Pilot")
    }

    @Test func watchedFractionUsesPercentageThenRuntime() {
        var item = MediaItem.test("1", position: Ticks(seconds: 30))
        item.runTime = Ticks(seconds: 120)
        #expect(item.watchedFraction == 0.25)
        item.userState.playedPercentage = 50
        #expect(item.watchedFraction == 0.5)
        item.userState.isPlayed = true
        #expect(item.watchedFraction == nil)
    }

    @Test func noPositionMeansPlayFromTheStart() {
        #expect(MediaItem.test("1").resumePosition == nil)
        #expect(MediaItem.test("1", position: Ticks(seconds: 5)).resumePosition == Ticks(seconds: 5))
    }
}
