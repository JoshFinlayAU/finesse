import Foundation

/// Which integration tests the running test plan wants. Xcode ignores a test plan's skipped and
/// selected lists for Swift Testing, so the plans set `FINESSE_TEST_SCOPE` instead:
/// `Integration.xctestplan` sets `no-playback`, and `Playback.xctestplan` sets `playback`.
/// Unset, as in `Full.xctestplan`, everything runs.
enum TestPlanScope {
    private static var value: String? {
        ProcessInfo.processInfo.environment["FINESSE_TEST_SCOPE"]
    }

    /// True in the Integration plan, which leaves streaming to the Playback plan.
    static var leavesOutPlayback: Bool { value == "no-playback" }

    /// True in the Playback plan, which runs only the streaming suites.
    static var playbackOnly: Bool { value == "playback" }
}
