import Testing
@testable import FinEsse

struct SubtitleRenderingFallbackTests {
    /// Plays in half-second steps, as the engine's time observer does. True if AVPlayer took over.
    private func play(_ fallback: inout SubtitleRenderingFallback, seconds: Double) -> Bool {
        var tookOver = false
        var left = seconds
        while left > 0 {
            let step = min(0.5, left)
            if fallback.played(step) {
                tookOver = true
            }
            left -= step
        }
        return tookOver
    }

    @Test func aSilentOutputHandsDrawingToAVPlayerAfterThePatience() {
        var fallback = SubtitleRenderingFallback()
        fallback.select(true)
        let early = play(&fallback, seconds: SubtitleRenderingFallback.patience - 1)
        #expect(!early)
        #expect(!fallback.isNative)
        let later = play(&fallback, seconds: 1)
        #expect(later)
        #expect(fallback.isNative)
    }

    @Test func itTakesOverOnlyOnce() {
        var fallback = SubtitleRenderingFallback()
        fallback.select(true)
        let first = play(&fallback, seconds: SubtitleRenderingFallback.patience)
        let again = play(&fallback, seconds: 30)
        #expect(first)
        #expect(!again)
        #expect(fallback.isNative)
    }

    /// tvOS 27 delivers updates, even empty ones, so it must never draw twice.
    @Test func anyDeliveryKeepsOurDrawing() {
        var fallback = SubtitleRenderingFallback()
        fallback.select(true)
        fallback.outputDelivered()
        let tookOver = play(&fallback, seconds: 120)
        #expect(!tookOver)
        #expect(!fallback.isNative)
    }

    @Test func noTrackMeansNothingToWaitFor() {
        var fallback = SubtitleRenderingFallback()
        fallback.select(false)
        let tookOver = play(&fallback, seconds: 120)
        #expect(!tookOver)
    }

    @Test func choosingAgainStartsTheWaitAgain() {
        var fallback = SubtitleRenderingFallback()
        fallback.select(true)
        let first = play(&fallback, seconds: SubtitleRenderingFallback.patience - 1)
        fallback.select(true)
        let second = play(&fallback, seconds: SubtitleRenderingFallback.patience - 1)
        let third = play(&fallback, seconds: 1)
        #expect(!first)
        #expect(!second)
        #expect(third)
    }

    @Test func turningSubtitlesOffStopsTheWait() {
        var fallback = SubtitleRenderingFallback()
        fallback.select(true)
        let before = play(&fallback, seconds: SubtitleRenderingFallback.patience - 1)
        fallback.select(false)
        let after = play(&fallback, seconds: 60)
        #expect(!before)
        #expect(!after)
    }

    /// Paused, or a seek's jump, which the engine doesn't pass on, adds nothing.
    @Test func onlyTimePlayedCounts() {
        var fallback = SubtitleRenderingFallback()
        fallback.select(true)
        let still = fallback.played(0)
        let backwards = fallback.played(-30)
        #expect(!still)
        #expect(!backwards)
        #expect(!fallback.isNative)
    }
}
