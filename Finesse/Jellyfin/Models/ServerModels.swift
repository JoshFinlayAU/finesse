import Foundation

/// Identifies this install to the server. `deviceID` must stay the same across launches.
struct DeviceIdentity: Hashable, Sendable, Codable {
    var clientName: String
    var clientVersion: String
    var deviceName: String
    var deviceID: String
}

struct ServerInfo: Hashable, Sendable, Codable {
    var id: String
    var name: String
    var version: String
}

/// A user shown on the sign-in screen. Hidden users are not listed by the server.
struct PublicUser: Identifiable, Hashable, Sendable, Codable {
    var id: String
    var name: String
    var hasPassword: Bool
    var primaryImageTag: String?
}

struct User: Identifiable, Hashable, Sendable, Codable {
    var id: String
    var name: String
    var primaryImageTag: String?
}

/// A signed-in user on one server. Holds the access token, so store it in the Keychain and never log it.
struct UserSession: Hashable, Sendable, Codable {
    var serverURL: URL
    var serverID: String
    var user: User
    var accessToken: String
}

/// Shows `code` to the user, then pass the whole value back to `quickConnectStatus` to poll.
struct QuickConnectRequest: Hashable, Sendable {
    var code: String
    var secret: String
    var isAuthenticated: Bool
}

enum JellyfinError: Error, Hashable, Sendable {
    case invalidServerURL
    case notAJellyfinServer
    case notSignedIn
    case invalidCredentials
    case forbidden
    case notFound
    case quickConnectDisabled
    case server(status: Int)
    case network(String)
    case decoding(String)
}
