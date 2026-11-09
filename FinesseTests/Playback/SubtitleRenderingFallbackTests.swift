import Testing
@testable import FinEsse

struct SubtitleRenderingFallbackTests {
    private func play(_ fallback: inout SubtitleRenderingFallback, seconds: Double) -> Bool {
        var tookOver = false
        var left = seconds
        while left > 0 {
            let step = min(0.5, left)
            tookOver = fallback.played(step) || tookOver
            left -= step
        }
        return tookOver
    }

    @Test func aSilentOutputHandsDrawingToAVPlayerAfterThePatience() {
        var fallback = SubtitleRenderingFallback()
        fallback.select(true)
        #expect(!play(&fallback, seconds: SubtitleRenderingFallback.patience - 1))
        #expect(!fallback.isNative)
        #expect(play(&fallback, seconds: 1))
        #expect(fallback.isNative)
    }

    @Test func itTakesOverOnlyOnce() {
        var fallback = SubtitleRenderingFallback()
        fallback.select(true)
        #expect(play(&fallback, seconds: SubtitleRenderingFallback.patience))
        #expect(!play(&fallback, seconds: 30))
        #expect(fallback.isNative)
    }

    /// tvOS 27 delivers updates, even empty ones, so it must never draw twice.
    @Test func anyDeliveryKeepsOurDrawing() {
        var fallback = SubtitleRenderingFallback()
        fallback.select(true)
        fallback.outputDelivered()
        #expect(!play(&fallback, seconds: 120))
        #expect(!fallback.isNative)
    }

    @Test func noTrackMeansNothingToWaitFor() {
        var fallback = SubtitleRenderingFallback()
        fallback.select(false)
        #expect(!play(&fallback, seconds: 120))
    }

    @Test func choosingAgainStartsTheWaitAgain() {
        var fallback = SubtitleRenderingFallback()
        fallback.select(true)
        #expect(!play(&fallback, seconds: SubtitleRenderingFallback.patience - 1))
        fallback.select(true)
        #expect(!play(&fallback, seconds: SubtitleRenderingFallback.patience - 1))
        #expect(play(&fallback, seconds: 1))
    }

    @Test func turningSubtitlesOffStopsTheWait() {
        var fallback = SubtitleRenderingFallback()
        fallback.select(true)
        #expect(!play(&fallback, seconds: SubtitleRenderingFallback.patience - 1))
        fallback.select(false)
        #expect(!play(&fallback, seconds: 60))
    }

    /// Paused, or a seek's jump, which the engine doesn't pass on, adds nothing.
    @Test func onlyTimePlayedCounts() {
        var fallback = SubtitleRenderingFallback()
        fallback.select(true)
        #expect(!fallback.played(0))
        #expect(!fallback.played(-30))
        #expect(!fallback.isNative)
    }
}
