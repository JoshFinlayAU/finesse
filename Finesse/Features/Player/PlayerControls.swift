import Foundation

enum PlayerPanel: String, CaseIterable, Hashable, Sendable {
    case audio
    case subtitles
    case playback
    case chapters
    case episodes
    case quality
    case info
}

/// What the remote does in the player, with no view or engine in it. During playback nothing
/// shows and left and right do nothing, so a thumb on the touch surface can't seek by accident.
/// A click pauses and starts a scrub, and only then do left and right move the position.
struct PlayerControls: Equatable {
    struct Scrub: Equatable {
        var origin: Ticks
        var target: Ticks
        /// Cancelling puts back what the click interrupted.
        var wasPlaying: Bool
    }

    enum Mode: Equatable {
        case hidden
        case bar
        case panel(PlayerPanel)
        case scrubbing(Scrub)
    }

    enum Event: Equatable {
        case swipeUp
        case swipeDown
        case moveLeft
        case moveRight
        /// `fraction` is the part of the touch surface swiped since the last one.
        case panned(Double)
        case click
        case back
        case playPause
        case openPanel(PlayerPanel)
        case activity
        case tick
    }

    enum Effect: Equatable {
        case pause
        case play
        case toggle
        case seek(Ticks)
        case exit
    }

    struct Context {
        var position: Ticks
        var duration: Ticks?
        var isPaused: Bool
        var now: Date
    }

    static let hideAfter: TimeInterval = 5
    static let clickScrubSeconds: TimeInterval = 10
    /// A full swipe across the touch surface covers this much, or the whole item if shorter.
    static let panScrubSeconds: TimeInterval = 600
    /// A swipe can also arrive as a move, which mustn't add ten seconds to what the pan already did.
    static let moveIgnoredAfterPan: TimeInterval = 0.5

    private(set) var mode = Mode.hidden
    private var lastActivity = Date.distantPast
    private var lastPan = Date.distantPast

    var scrub: Scrub? {
        if case .scrubbing(let scrub) = mode { scrub } else { nil }
    }

    var panel: PlayerPanel? {
        if case .panel(let panel) = mode { panel } else { nil }
    }

    /// True when something covers the bottom of the screen.
    var isShowing: Bool {
        mode != .hidden
    }

    /// True when focus belongs to the bar or a panel rather than the invisible remote surface.
    var hasButtons: Bool {
        switch mode {
        case .bar, .panel: true
        case .hidden, .scrubbing: false
        }
    }

    mutating func reset() {
        mode = .hidden
    }

    mutating func handle(_ event: Event, _ context: Context) -> [Effect] {
        switch mode {
        case .hidden: handleHidden(event, context)
        case .bar: handleBar(event, context)
        case .panel: handlePanel(event, context)
        case .scrubbing(let scrub): handleScrub(event, scrub, context)
        }
    }

    private mutating func handleHidden(_ event: Event, _ context: Context) -> [Effect] {
        switch event {
        case .swipeUp:
            showBar(context)
            return []
        case .click:
            return startScrub(context)
        case .back:
            return [.exit]
        case .playPause:
            return [.toggle]
        default:
            return []
        }
    }

    private mutating func handleBar(_ event: Event, _ context: Context) -> [Effect] {
        switch event {
        case .swipeDown, .back:
            mode = .hidden
        case .click:
            return startScrub(context)
        case .playPause:
            lastActivity = context.now
            return [.toggle]
        case .openPanel(let panel):
            mode = .panel(panel)
        case .activity, .swipeUp, .moveLeft, .moveRight:
            lastActivity = context.now
        case .tick:
            if !context.isPaused, context.now.timeIntervalSince(lastActivity) >= Self.hideAfter {
                mode = .hidden
            }
        case .panned:
            break
        }
        return []
    }

    private mutating func handlePanel(_ event: Event, _ context: Context) -> [Effect] {
        switch event {
        case .back:
            showBar(context)
        case .click:
            return startScrub(context)
        case .playPause:
            return [.toggle]
        case .openPanel(let panel):
            mode = .panel(panel)
        default:
            break
        }
        return []
    }

    private mutating func handleScrub(_ event: Event, _ scrub: Scrub, _ context: Context) -> [Effect] {
        switch event {
        case .moveLeft:
            move(scrub, bySeconds: -Self.clickScrubSeconds, unlessPanning: context)
        case .moveRight:
            move(scrub, bySeconds: Self.clickScrubSeconds, unlessPanning: context)
        case .panned(let fraction):
            lastPan = context.now
            let span = min(context.duration?.seconds ?? Self.panScrubSeconds, Self.panScrubSeconds)
            setTarget(scrub, scrub.target.seconds + fraction * span, context)
        case .click, .playPause:
            mode = .hidden
            return scrub.target == scrub.origin ? [.play] : [.seek(scrub.target), .play]
        case .back:
            mode = .hidden
            return scrub.wasPlaying ? [.play] : []
        default:
            break
        }
        return []
    }

    private mutating func showBar(_ context: Context) {
        mode = .bar
        lastActivity = context.now
    }

    private mutating func startScrub(_ context: Context) -> [Effect] {
        mode = .scrubbing(Scrub(origin: context.position, target: context.position, wasPlaying: !context.isPaused))
        return context.isPaused ? [] : [.pause]
    }

    private mutating func move(_ scrub: Scrub, bySeconds seconds: TimeInterval, unlessPanning context: Context) {
        guard context.now.timeIntervalSince(lastPan) >= Self.moveIgnoredAfterPan else {
            return
        }
        setTarget(scrub, scrub.target.seconds + seconds, context)
    }

    private mutating func setTarget(_ scrub: Scrub, _ seconds: TimeInterval, _ context: Context) {
        var target = max(seconds, 0)
        if let duration = context.duration?.seconds, duration > 0 {
            target = min(target, duration)
        }
        var scrub = scrub
        scrub.target = Ticks(seconds: target)
        mode = .scrubbing(scrub)
    }
}
