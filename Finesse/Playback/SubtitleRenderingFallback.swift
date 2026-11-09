/// When AVPlayer should draw subtitles itself rather than hand them to us.
///
/// We normally take AVPlayer's lines through `AVPlayerItemLegibleOutput` and draw them ourselves, so the
/// subtitle options apply. On the tvOS 26.5 simulator that output delivers nothing at all, not even
/// empty updates, while tvOS 27 delivers them at once. So once a track has been selected and playback
/// has moved on a few seconds with no delivery, AVPlayer draws them instead. They show unstyled, and
/// the size, position and background options don't apply. It stays that way until the next item.
struct SubtitleRenderingFallback {
    /// Seconds of playback with a track selected and nothing delivered before AVPlayer takes over.
    static let patience = 8.0

    private(set) var isNative = false
    private var trackSelected = false
    private var delivered = false
    private var playedSinceSelection = 0.0

    /// A track was chosen, or turned off. Waiting starts again from here.
    mutating func select(_ selected: Bool) {
        trackSelected = selected
        playedSinceSelection = 0
    }

    /// The output delivered something, even an empty update, so it works and we keep drawing.
    mutating func outputDelivered() {
        delivered = true
    }

    /// Playback moved on by `seconds`. Returns true once, at the moment AVPlayer should start drawing.
    mutating func played(_ seconds: Double) -> Bool {
        guard !isNative, !delivered, trackSelected, seconds > 0 else {
            return false
        }
        playedSinceSelection += seconds
        guard playedSinceSelection >= Self.patience else {
            return false
        }
        isNative = true
        return true
    }
}
