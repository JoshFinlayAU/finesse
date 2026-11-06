import Foundation
import os

/// The order and timing of what the Siri Remote sends, for settling on real hardware what the
/// simulator can't show: whether a swipe arrives as a pan, a move or both, in which order, how far
/// a full swipe really goes, and how much a resting thumb drifts. Nothing is compiled in a release
/// build. See memory/player-hud.md for how to read it.
enum PlayerRemoteLog {
    #if DEBUG
    private static let logger = Logger(subsystem: "au.com.athenanetworks.finesse", category: "remote")
    private static let started = ContinuousClock.now
    #endif

    @inline(__always)
    static func note(_ message: @autoclosure () -> String) {
        #if DEBUG
        let elapsed = (ContinuousClock.now - started).components
        let milliseconds = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
        let line = "FINESSE-REMOTE \(milliseconds)ms \(message())"
        logger.notice("\(line, privacy: .public)")
        print(line)
        #endif
    }
}
