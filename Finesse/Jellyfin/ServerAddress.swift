import Foundation

enum ServerAddress {
    static let defaultHTTPPort = 8096

    /// Turns what a user typed into a server URL. A bare host gets `http` and Jellyfin's
    /// default port. An explicit scheme is kept as typed and gets no port added, since a
    /// server behind a reverse proxy normally answers on the scheme's own port.
    static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasScheme = text.contains("://")
        while text.hasSuffix("/") {
            text.removeLast()
        }
        guard !text.isEmpty else { return nil }

        guard var components = URLComponents(string: hasScheme ? text : "http://\(text)"),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty
        else { return nil }

        components.scheme = scheme
        if !hasScheme, components.port == nil {
            components.port = defaultHTTPPort
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
