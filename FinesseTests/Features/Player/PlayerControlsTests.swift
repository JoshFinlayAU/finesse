import Foundation
import Testing
@testable import FinEsse

/// The remote's rules with no view or engine involved.
@Suite struct PlayerControlsTests {
    private let start = Date(timeIntervalSince1970: 1000)

    private func context(
        position: Double = 100,
        duration: Double? = 1000,
        paused: Bool = false,
        after seconds: TimeInterval = 0
    ) -> PlayerControls.Context {
        .init(
            position: Ticks(seconds: position),
            duration: duration.map(Ticks.init(seconds:)),
            isPaused: paused,
            now: start.addingTimeInterval(seconds)
        )
    }

    private func scrubbing(paused: Bool = false) -> PlayerControls {
        var controls = PlayerControls()
        _ = controls.handle(.click, context(paused: paused))
        return controls
    }

    // MARK: Nothing showing

    @Test func playingShowsNothing() {
        #expect(PlayerControls().mode == .hidden)
        #expect(!PlayerControls().isShowing)
    }

    @Test func swipeUpShowsTheBarAndDoesNothingElse() {
        var controls = PlayerControls()
        #expect(controls.handle(.swipeUp, context()).isEmpty)
        #expect(controls.mode == .bar)
    }

    @Test(arguments: [PlayerControls.Event.moveLeft, .moveRight, .panned(0.5), .swipeDown, .tick, .activity])
    func theseDoNothingWhilePlaying(event: PlayerControls.Event) {
        var controls = PlayerControls()
        #expect(controls.handle(event, context()).isEmpty)
        #expect(controls.mode == .hidden)
    }

    @Test func clickPausesAndStartsAScrubFromThePosition() throws {
        var controls = PlayerControls()
        #expect(controls.handle(.click, context()) == [.pause])
        let scrub = try #require(controls.scrub)
        #expect(scrub.origin == Ticks(seconds: 100))
        #expect(scrub.target == Ticks(seconds: 100))
        #expect(scrub.wasPlaying)
    }

    @Test func clickWhileAlreadyPausedDoesNotPauseAgain() {
        var controls = PlayerControls()
        #expect(controls.handle(.click, context(paused: true)).isEmpty)
        #expect(controls.scrub?.wasPlaying == false)
    }

    @Test func backLeavesThePlayer() {
        var controls = PlayerControls()
        #expect(controls.handle(.back, context()) == [.exit])
    }

    @Test func playPauseTogglesAndShowsNothing() {
        var controls = PlayerControls()
        #expect(controls.handle(.playPause, context()) == [.toggle])
        #expect(controls.mode == .hidden)
    }

    // MARK: Bar

    @Test func swipeDownAndBackDismissTheBarWithoutLeaving() {
        for event in [PlayerControls.Event.swipeDown, .back] {
            var controls = PlayerControls()
            _ = controls.handle(.swipeUp, context())
            #expect(controls.handle(event, context()).isEmpty)
            #expect(controls.mode == .hidden)
        }
    }

    @Test func theBarHidesAfterTheTimeout() {
        var controls = PlayerControls()
        _ = controls.handle(.swipeUp, context())
        _ = controls.handle(.tick, context(after: PlayerControls.hideAfter - 0.1))
        #expect(controls.mode == .bar)
        _ = controls.handle(.tick, context(after: PlayerControls.hideAfter))
        #expect(controls.mode == .hidden)
    }

    @Test func activityRestartsTheTimeout() {
        var controls = PlayerControls()
        _ = controls.handle(.swipeUp, context())
        _ = controls.handle(.activity, context(after: 4))
        _ = controls.handle(.tick, context(after: PlayerControls.hideAfter + 1))
        #expect(controls.mode == .bar)
    }

    @Test func theBarStaysWhilePaused() {
        var controls = PlayerControls()
        _ = controls.handle(.swipeUp, context())
        _ = controls.handle(.tick, context(paused: true, after: 60))
        #expect(controls.mode == .bar)
    }

    @Test func playPauseOnTheBarTogglesAndKeepsItUp() {
        var controls = PlayerControls()
        _ = controls.handle(.swipeUp, context())
        #expect(controls.handle(.playPause, context(after: 4)) == [.toggle])
        _ = controls.handle(.tick, context(after: PlayerControls.hideAfter + 1))
        #expect(controls.mode == .bar)
    }

    @Test func leftAndRightOnTheBarOnlyMoveFocus() {
        var controls = PlayerControls()
        _ = controls.handle(.swipeUp, context())
        #expect(controls.handle(.moveRight, context()).isEmpty)
        #expect(controls.mode == .bar)
    }

    @Test func theBarsMainButtonStartsAScrubLikeAnyOtherClick() {
        var controls = PlayerControls()
        _ = controls.handle(.swipeUp, context())
        #expect(controls.handle(.click, context()) == [.pause])
        #expect(controls.scrub != nil)
    }

    // MARK: Panels

    @Test func panelsOpenFromTheBarAndBackReturnsToIt() {
        var controls = PlayerControls()
        _ = controls.handle(.swipeUp, context())
        _ = controls.handle(.openPanel(.audio), context())
        #expect(controls.panel == .audio)
        #expect(controls.hasButtons)
        #expect(controls.handle(.back, context()).isEmpty)
        #expect(controls.mode == .bar)
    }

    @Test func aPanelDoesNotOpenWithoutTheBar() {
        var controls = PlayerControls()
        _ = controls.handle(.openPanel(.audio), context())
        #expect(controls.mode == .hidden)
    }

    @Test func anotherPanelCanOpenFromAPanel() {
        var controls = PlayerControls()
        _ = controls.handle(.swipeUp, context())
        _ = controls.handle(.openPanel(.audio), context())
        _ = controls.handle(.openPanel(.info), context())
        #expect(controls.panel == .info)
    }

    @Test func aPanelStaysOpenThroughTheTimeoutAndSwipes() {
        var controls = PlayerControls()
        _ = controls.handle(.swipeUp, context())
        _ = controls.handle(.openPanel(.quality), context())
        for event in [PlayerControls.Event.tick, .swipeDown, .swipeUp, .moveLeft, .moveRight] {
            #expect(controls.handle(event, context(after: 600)).isEmpty)
            #expect(controls.panel == .quality)
        }
    }

    @Test func playPauseWorksInAPanel() {
        var controls = PlayerControls()
        _ = controls.handle(.swipeUp, context())
        _ = controls.handle(.openPanel(.audio), context())
        #expect(controls.handle(.playPause, context()) == [.toggle])
        #expect(controls.panel == .audio)
    }

    @Test func theBarsMainButtonStillWorksWithAPanelOpen() {
        var controls = PlayerControls()
        _ = controls.handle(.swipeUp, context())
        _ = controls.handle(.openPanel(.audio), context())
        #expect(controls.handle(.click, context()) == [.pause])
        #expect(controls.scrub != nil)
    }

    @Test func comingBackFromAPanelRestartsTheTimeout() {
        var controls = PlayerControls()
        _ = controls.handle(.swipeUp, context())
        _ = controls.handle(.openPanel(.audio), context())
        _ = controls.handle(.back, context(after: 600))
        _ = controls.handle(.tick, context(after: 601))
        #expect(controls.mode == .bar)
    }

    // MARK: Scrubbing

    @Test func movesAddUpAndStayWithinTheItem() {
        var controls = scrubbing()
        _ = controls.handle(.moveRight, context())
        _ = controls.handle(.moveRight, context())
        #expect(controls.scrub?.target == Ticks(seconds: 120))
        _ = controls.handle(.moveLeft, context())
        #expect(controls.scrub?.target == Ticks(seconds: 110))

        for _ in 0..<20 { _ = controls.handle(.moveLeft, context()) }
        #expect(controls.scrub?.target == .zero)
        for _ in 0..<120 { _ = controls.handle(.moveRight, context()) }
        #expect(controls.scrub?.target == Ticks(seconds: 1000))
    }

    @Test func aFullSwipeCoversTenMinutesAtMost() {
        var controls = scrubbing()
        _ = controls.handle(.panned(0.5), context())
        #expect(controls.scrub?.target == Ticks(seconds: 400))
    }

    @Test func aShortItemScalesASwipeToItsLength() {
        var controls = PlayerControls()
        _ = controls.handle(.click, context(position: 10, duration: 100))
        _ = controls.handle(.panned(0.5), context(position: 10, duration: 100))
        #expect(controls.scrub?.target == Ticks(seconds: 60))
    }

    @Test func aMoveJustAfterAPanIsTheSameSwipeAndIgnored() {
        var controls = scrubbing()
        _ = controls.handle(.panned(0.1), context())
        let afterPan = controls.scrub?.target
        _ = controls.handle(.moveRight, context(after: PlayerControls.moveIgnoredAfterPan - 0.1))
        #expect(controls.scrub?.target == afterPan)
        _ = controls.handle(.moveRight, context(after: PlayerControls.moveIgnoredAfterPan))
        #expect(controls.scrub?.target != afterPan)
    }

    @Test func clickCommitsTheSeekAndResumes() {
        var controls = scrubbing()
        _ = controls.handle(.moveRight, context())
        #expect(controls.handle(.click, context()) == [.seek(Ticks(seconds: 110)), .play])
        #expect(controls.mode == .hidden)
    }

    @Test func clickWithoutMovingOnlyResumes() {
        var controls = scrubbing()
        #expect(controls.handle(.click, context()) == [.play])
    }

    @Test func aCommitResumesEvenFromAPauseBeforeTheClick() {
        var controls = scrubbing(paused: true)
        _ = controls.handle(.moveRight, context(paused: true))
        #expect(controls.handle(.click, context(paused: true)) == [.seek(Ticks(seconds: 110)), .play])
    }

    @Test func playPauseCommitsLikeAClick() {
        var controls = scrubbing()
        _ = controls.handle(.moveRight, context())
        #expect(controls.handle(.playPause, context()) == [.seek(Ticks(seconds: 110)), .play])
    }

    @Test func backCancelsAndResumesWhatTheClickPaused() {
        var controls = scrubbing()
        _ = controls.handle(.moveRight, context())
        #expect(controls.handle(.back, context()) == [.play])
        #expect(controls.mode == .hidden)
    }

    @Test func backStaysPausedWhenItWasPausedBeforeTheClick() {
        var controls = scrubbing(paused: true)
        _ = controls.handle(.moveRight, context(paused: true))
        #expect(controls.handle(.back, context(paused: true)).isEmpty)
        #expect(controls.mode == .hidden)
    }

    @Test func scrubbingNeverTimesOutAndIgnoresVerticalSwipes() {
        var controls = scrubbing()
        for event in [PlayerControls.Event.tick, .swipeUp, .swipeDown, .activity] {
            #expect(controls.handle(event, context(after: 600)).isEmpty)
            #expect(controls.scrub != nil)
        }
    }

    @Test func resetHidesEverything() {
        var controls = scrubbing()
        controls.reset()
        #expect(controls.mode == .hidden)
    }
}
