import Testing
@testable import FinEsse

/// The simulator plays through the build Mac's speakers, so test runs there must make no sound.
@MainActor
struct PlaybackAudioTests {
    @Test func debugBuildsInTheSimulatorAreSilentByDefault() {
        #expect(PlaybackAudio.silenced(arguments: [], isSimulator: true, isDebug: true))
        #expect(PlaybackAudio.silenced(arguments: ["-FinesseFakeServer"], isSimulator: true, isDebug: true))
    }

    @Test func soundCanBeAskedForInTheSimulator() {
        #expect(!PlaybackAudio.silenced(arguments: ["-FinesseAudio"], isSimulator: true, isDebug: true))
    }

    @Test func muteSilencesADebugBuildOnADevice() {
        #expect(!PlaybackAudio.silenced(arguments: [], isSimulator: false, isDebug: true))
        #expect(PlaybackAudio.silenced(arguments: ["-FinesseMuteAudio"], isSimulator: false, isDebug: true))
        #expect(PlaybackAudio.silenced(arguments: ["-FinesseMuteAudio", "-FinesseAudio"], isSimulator: true, isDebug: true))
    }

    @Test func releaseBuildsAlwaysPlaySound() {
        #expect(!PlaybackAudio.silenced(arguments: [], isSimulator: true, isDebug: false))
        #expect(!PlaybackAudio.silenced(arguments: ["-FinesseMuteAudio"], isSimulator: true, isDebug: false))
    }

    /// These tests run in the simulator, so this is the setting every other run there gets.
    @Test func thisRunIsSilenced() {
        #expect(PlaybackAudio.isSilenced)
    }

    @Test func avPlayerReportsItselfMuted() {
        #expect(AVPlayerEngine().isSilent)
    }

    /// Read back from mpv itself, not from the options it was given.
    @Test func mpvReportsItselfMuted() throws {
        let engine = MPVEngine()
        defer { engine.stop() }
        #expect(engine.isSilent)
        #expect(engine.property("mute") == "yes")
        #expect(engine.property("volume").flatMap(Double.init) == 0)
    }
}
