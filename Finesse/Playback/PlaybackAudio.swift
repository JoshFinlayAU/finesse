import Foundation

/// Whether playback should make any sound.
///
/// DEBUG builds in the simulator are silent unless launched with `-FinesseAudio`, because the
/// simulator plays through the build Mac's speakers. That covers UI tests, integration tests and
/// screenshot runs without each one having to remember a flag. `-FinesseMuteAudio` silences a DEBUG
/// build anywhere, including on a device. Release builds always play sound.
enum PlaybackAudio {
    static let isSilenced: Bool = silenced(arguments: ProcessInfo.processInfo.arguments)

    static func silenced(arguments: [String], isSimulator: Bool = runsInSimulator, isDebug: Bool = isDebugBuild) -> Bool {
        guard isDebug else {
            return false
        }
        if arguments.contains("-FinesseMuteAudio") {
            return true
        }
        return isSimulator && !arguments.contains("-FinesseAudio")
    }

    static var runsInSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
