import AVFoundation
import CoreGraphics
import Foundation
import MediaAccessibility

struct SubtitleColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(_ color: CGColor, opacity: Double) {
        guard let rgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let parts = rgb.components, parts.count >= 3 else {
            return nil
        }
        self.init(red: parts[0], green: parts[1], blue: parts[2], alpha: opacity)
    }
}

/// The person's system-wide caption settings. Only what they've actually overridden has a value,
/// so an unchanged setting leaves the player's own look alone.
struct SystemCaptionStyle: Hashable, Sendable {
    var scale: Double?
    var textColor: SubtitleColor?
    var backgroundColor: SubtitleColor?
    /// Subtitles should come on by themselves when nothing else has chosen a track.
    var isAlwaysOn = false
    var prefersSDH = false

    /// Reads Settings > Accessibility > Subtitles and Captioning. Changes apply from the next playback.
    static func current() -> SystemCaptionStyle {
        var style = SystemCaptionStyle()
        var behavior = MACaptionAppearanceBehavior.useContentIfAvailable

        let size = MACaptionAppearanceGetRelativeCharacterSize(.user, &behavior)
        if behavior == .useValue { style.scale = Double(size) }

        let opacity = MACaptionAppearanceGetForegroundOpacity(.user, nil)
        let text = MACaptionAppearanceCopyForegroundColor(.user, &behavior).takeRetainedValue()
        if behavior == .useValue { style.textColor = SubtitleColor(text, opacity: Double(opacity)) }

        let backgroundOpacity = MACaptionAppearanceGetBackgroundOpacity(.user, nil)
        let background = MACaptionAppearanceCopyBackgroundColor(.user, &behavior).takeRetainedValue()
        if behavior == .useValue, backgroundOpacity > 0 {
            style.backgroundColor = SubtitleColor(background, opacity: Double(backgroundOpacity))
        }

        style.isAlwaysOn = MACaptionAppearanceGetDisplayType(.user) == .alwaysOn
        let characteristics = MACaptionAppearanceCopyPreferredCaptioningMediaCharacteristics(.user).takeRetainedValue() as? [String] ?? []
        style.prefersSDH = characteristics.contains(AVMediaCharacteristic.transcribesSpokenDialogForAccessibility.rawValue)
        return style
    }

    /// The track to turn on when captions are set to always on and the server hasn't chosen one.
    /// Stays off rather than show subtitles in a language the person may not read.
    func defaultSubtitle(in streams: [MediaStreamInfo], languages: [String] = Locale.preferredLanguages) -> Int? {
        guard isAlwaysOn else {
            return nil
        }
        let wanted = Set(languages.compactMap { Locale(identifier: $0).language.languageCode?.identifier(.alpha3) })
        let matching = streams.filter { stream in
            guard stream.kind == .subtitle, let language = stream.language else {
                return false
            }
            return wanted.contains(language.lowercased())
        }
        let sdh = matching.first { Self.isSDH($0) }
        let plain = matching.first { !Self.isSDH($0) && !$0.isForced }
        return (prefersSDH ? sdh ?? plain : plain ?? sdh)?.index
    }

    /// Jellyfin puts this in the track's title.
    private static func isSDH(_ stream: MediaStreamInfo) -> Bool {
        let title = "\(stream.title ?? "") \(stream.displayTitle ?? "")".lowercased()
        return ["sdh", "hearing", "[cc]", " cc "].contains { title.contains($0) }
    }
}
