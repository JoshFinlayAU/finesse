import Foundation

/// What a person would want the same on every video. Speed and timing offsets aren't here: speed
/// is a choice for this sitting, and an offset only fixes the file it was set for.
struct PlayerPreferences: Codable, Equatable, Sendable {
    /// Nil until the person picks a size here, and until then the system's caption size applies.
    var subtitleScale: Double?
    var subtitleRaise = 0
    var pictureMode = PictureMode.fit
    var maxBitrate: Int?
}

/// Kept for each user, so one person's choices don't follow another across a user switch.
struct PlayerPreferenceStore {
    var defaults: UserDefaults = .standard

    private func key(_ userID: String) -> String {
        "playerPreferences.\(userID)"
    }

    func load(userID: String) -> PlayerPreferences {
        defaults.data(forKey: key(userID))
            .flatMap { try? JSONDecoder().decode(PlayerPreferences.self, from: $0) } ?? PlayerPreferences()
    }

    func save(_ preferences: PlayerPreferences, userID: String) {
        defaults.set(try? JSONEncoder().encode(preferences), forKey: key(userID))
    }
}
