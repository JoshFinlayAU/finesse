import Foundation

/// Something that changed on the server while the app was open. Screens refresh what they show
/// in place when one arrives.
enum ServerEvent: Equatable, Sendable {
    /// Titles were added, changed or removed, as when a library scan finds new episodes.
    case libraryChanged(LibraryChange)
    /// The signed-in user's watched state, progress or favourites changed, here or on another device.
    case userDataChanged([UserDataChange])
    /// Anything may have changed: the app came back to the front, the connection came back after
    /// a gap, or there's no connection and the fallback timer came round.
    case catchUp
}

struct LibraryChange: Equatable, Sendable {
    var added: [String] = []
    var updated: [String] = []
    var removed: [String] = []
}

struct UserDataChange: Equatable, Sendable {
    var itemID: String
    var isPlayed: Bool
    var playbackPosition: Ticks
    var isFavorite: Bool
}

/// One message from the server's `/socket`, as Jellyfin 12.4 sends them.
enum LiveMessage: Equatable, Sendable {
    /// The server will drop a connection that's quiet for this many seconds.
    case forceKeepAlive(seconds: Int)
    case keepAlive
    case event(ServerEvent)
    /// Anything else, including messages for other users and kinds this app doesn't use.
    case ignored

    /// What the app sends to keep the connection open.
    static let keepAliveText = #"{"MessageType":"KeepAlive"}"#

    /// Reads one message. User data for anyone other than `userID` is ignored.
    static func parse(_ text: String, userID: String) -> LiveMessage {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = object["MessageType"] as? String
        else { return .ignored }
        let data = object["Data"]
        switch type {
        case "ForceKeepAlive":
            guard let seconds = (data as? NSNumber)?.intValue, seconds > 0 else { return .ignored }
            return .forceKeepAlive(seconds: seconds)
        case "KeepAlive":
            return .keepAlive
        case "LibraryChanged":
            guard let data = data as? [String: Any] else { return .ignored }
            let ids = { (key: String) in (data[key] as? [String]) ?? [] }
            let change = LibraryChange(added: ids("ItemsAdded"), updated: ids("ItemsUpdated"), removed: ids("ItemsRemoved"))
            // A scan that only touched folders still changes what a library shows.
            let folders = ids("FoldersAddedTo") + ids("FoldersRemovedFrom") + ids("CollectionFolders")
            guard change != LibraryChange() || !folders.isEmpty else { return .ignored }
            return .event(.libraryChanged(change))
        case "UserDataChanged":
            guard let data = data as? [String: Any],
                  let user = data["UserId"] as? String, sameID(user, userID),
                  let list = data["UserDataList"] as? [[String: Any]]
            else { return .ignored }
            let changes = list.compactMap { entry -> UserDataChange? in
                guard let id = entry["ItemId"] as? String else { return nil }
                return UserDataChange(
                    itemID: id,
                    isPlayed: entry["Played"] as? Bool ?? false,
                    playbackPosition: Ticks(rawValue: (entry["PlaybackPositionTicks"] as? NSNumber)?.int64Value ?? 0),
                    isFavorite: entry["IsFavorite"] as? Bool ?? false
                )
            }
            return changes.isEmpty ? .ignored : .event(.userDataChanged(changes))
        default:
            return .ignored
        }
    }

    /// The server writes IDs without dashes in some places and with them in others.
    private static func sameID(_ a: String, _ b: String) -> Bool {
        a.replacingOccurrences(of: "-", with: "").lowercased() == b.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

/// Hands each event to every screen listening. A screen listens only while it's showing.
final class ServerEventHub: @unchecked Sendable {
    private let lock = NSLock()
    private var listeners: [UUID: AsyncStream<ServerEvent>.Continuation] = [:]

    init() {}

    func stream() -> AsyncStream<ServerEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation in
            let id = UUID()
            lock.withLock { listeners[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { self.listeners[id] = nil }
            }
        }
    }

    func send(_ event: ServerEvent) {
        for listener in lock.withLock({ Array(listeners.values) }) {
            listener.yield(event)
        }
    }

    var listenerCount: Int {
        lock.withLock { listeners.count }
    }
}

/// One open connection to the server's `/socket`.
protocol LiveSocket: Sendable {
    func send(_ text: String) async throws
    /// Waits for the next message. Throws once the connection has gone.
    func receive() async throws -> String
    func close()
}

/// A client that can open a live connection for the signed-in user.
protocol LiveEventSource: Sendable {
    /// The connection, and the ID of the user it's for.
    func openLiveSocket() async throws -> (socket: any LiveSocket, userID: String)
}
