import Foundation

enum PictureMode: String, CaseIterable, Hashable, Sendable, Codable {
    case fit
    case fill
    case stretch
}

/// The picture, sound and subtitle settings a session keeps across engine moves.
struct PlaybackOptions: Hashable, Sendable {
    var rate = 1.0
    var pictureMode = PictureMode.fit
    /// 1 is the engine's normal subtitle size.
    var subtitleScale = 1.0
    /// Percent of the screen height above the normal subtitle position.
    var subtitleRaise = 0
    /// Nil leaves the engine's own look. These come from the system's caption settings.
    var subtitleTextColor: SubtitleColor?
    var subtitleBackgroundColor: SubtitleColor?
    /// Positive shows subtitles later.
    var subtitleDelay: TimeInterval = 0
    /// Positive plays audio later.
    var audioDelay: TimeInterval = 0

    static let rates = [0.5, 0.75, 1, 1.25, 1.5, 2]
    static let subtitleScales = 0.5...2.0
    static let subtitleRaises = 0...40
    static let delays: ClosedRange<TimeInterval> = -10...10

    /// What's asked of an engine, including anything that differs from normal.
    var optionsInUse: Set<PlaybackOption> {
        var used: Set<PlaybackOption> = []
        if rate != 1 { used.insert(.rate) }
        if pictureMode != .fit { used.insert(.pictureMode) }
        if subtitleScale != 1 || subtitleRaise != 0 { used.insert(.subtitleStyle) }
        if subtitleDelay != 0 { used.insert(.subtitleDelay) }
        if audioDelay != 0 { used.insert(.audioDelay) }
        return used
    }

    /// For telling whether one option changed. Subtitle size and position count as one.
    func value(of option: PlaybackOption) -> [Double] {
        switch option {
        case .rate: [rate]
        case .pictureMode: [Double(PictureMode.allCases.firstIndex(of: pictureMode) ?? 0)]
        case .subtitleStyle: [subtitleScale, Double(subtitleRaise)]
        case .subtitleDelay: [subtitleDelay]
        case .audioDelay: [audioDelay]
        }
    }
}

enum PlaybackOption: Hashable, Sendable, CaseIterable {
    case rate
    case pictureMode
    case subtitleStyle
    case subtitleDelay
    case audioDelay

    /// AVPlayer has no public way to shift audio or subtitle timing.
    func isSupported(by engine: PlaybackEngineKind) -> Bool {
        switch self {
        case .rate, .pictureMode, .subtitleStyle: true
        case .subtitleDelay, .audioDelay: engine == .mpv
        }
    }
}

enum PlaybackOptionAvailability: Hashable, Sendable {
    case available
    /// Changing it moves playback to the other engine, at the same position.
    case movesEngine
    case unavailable(String)
}
