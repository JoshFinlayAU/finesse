import Foundation

/// What the Top Shelf asks the app to open. It only ever names an item and whose it is. The URL
/// is handed to the system, so it must never hold a token.
struct FinesseDeepLink: Hashable, Sendable {
    enum Action: String, Sendable {
        case play
        case detail
    }

    static let scheme = "finesse"

    var action: Action
    var itemID: String
    /// `UserSession.accountKey` of the user whose shelf this came from.
    var account: String

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = action.rawValue
        components.queryItems = [
            URLQueryItem(name: "item", value: itemID),
            URLQueryItem(name: "account", value: account),
        ]
        return components.url
    }

    init(action: Action, itemID: String, account: String) {
        self.action = action
        self.itemID = itemID
        self.account = account
    }

    /// Anything else can open this scheme, so a link missing a part is ignored rather than guessed at.
    init?(url: URL) {
        guard url.scheme == Self.scheme,
              let action = url.host().flatMap(Action.init(rawValue:)),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let itemID = items.first(where: { $0.name == "item" })?.value, !itemID.isEmpty,
              let account = items.first(where: { $0.name == "account" })?.value, !account.isEmpty else {
            return nil
        }
        self.init(action: action, itemID: itemID, account: account)
    }
}
