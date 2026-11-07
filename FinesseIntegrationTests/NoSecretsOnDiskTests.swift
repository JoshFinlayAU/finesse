import Foundation
import Testing
@testable import FinEsse

/// These tests run inside the app, so anything sent through `URLSession.shared` goes through the app's
/// own cache. A run once left the test password and a token in the app's `Cache.db` that way. This
/// sends both through it on purpose, then searches the app's folders for them. Reports paths only.
@Suite(.serialized, .enabled(if: SecretsServer.current != nil, "JELLYFIN_* variables not set"))
struct NoSecretsOnDiskTests {
    @Test func credentialsSentThroughTheSharedSessionStayOffDisk() async throws {
        let server = try #require(SecretsServer.current)
        let authorization = #"MediaBrowser Client="Finesse Tests", Device="Simulator", DeviceId="finesse-integration-secrets", Version="0""#

        var signIn = URLRequest(url: server.url.appending(path: "Users/AuthenticateByName"))
        signIn.httpMethod = "POST"
        signIn.setValue("application/json", forHTTPHeaderField: "Content-Type")
        signIn.setValue(authorization, forHTTPHeaderField: "Authorization")
        signIn.httpBody = try JSONEncoder().encode(["Username": server.username, "Pw": server.password])
        let (data, _) = try await URLSession.shared.data(for: signIn)
        let token = try #require(try JSONDecoder().decode(SignedIn.self, from: data).AccessToken)

        var me = URLRequest(url: server.url.appending(path: "Users/Me"))
        me.setValue(authorization + #", Token="\#(token)""#, forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: me)
        var keyed = URLComponents(url: server.url.appending(path: "System/Info"), resolvingAgainstBaseURL: false)!
        keyed.queryItems = [URLQueryItem(name: "ApiKey", value: token)]
        _ = try await URLSession.shared.data(from: try #require(keyed.url))

        // The cache writes after the response has been handed over.
        try await Task.sleep(for: .seconds(5))
        let found = SecretSearch(secrets: [server.password, token]).search(URL(filePath: NSHomeDirectory()))

        var logout = URLRequest(url: server.url.appending(path: "Sessions/Logout"))
        logout.httpMethod = "POST"
        logout.setValue(authorization + #", Token="\#(token)""#, forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .ephemeral)
        _ = try? await session.data(for: logout)
        session.invalidateAndCancel()

        #expect(found.isEmpty, "The password or token is on disk in: \(found.joined(separator: ", "))")
    }

    /// A search that can't find what it's looking for proves nothing.
    @Test func theSearchFindsEachFormASecretTakes() {
        let search = SecretSearch(secrets: ["p@ss/word+1"])
        for form in search.forms {
            #expect(search.contains(Data("x".utf8) + form + Data("y".utf8)))
        }
        #expect(search.forms.count >= 5)
        #expect(!search.contains(Data("nothing here".utf8)))
    }
}

private struct SignedIn: Decodable {
    let AccessToken: String?
}

private struct SecretsServer {
    let url: URL
    let username: String
    let password: String

    static var current: SecretsServer? {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["JELLYFIN_URL"].flatMap(URL.init(string:)),
              let username = environment["JELLYFIN_USERNAME"],
              let password = environment["JELLYFIN_PASSWORD"] else {
            return nil
        }
        return SecretsServer(url: url, username: username, password: password)
    }
}

/// The ways a secret appears in a cache: as sent, JSON-escaped, percent-encoded, UTF-16 and base64.
private struct SecretSearch {
    let forms: [Data]

    init(secrets: [String]) {
        var forms: [Data] = []
        for secret in secrets {
            let json = String(decoding: try! JSONEncoder().encode(secret), as: UTF8.self).dropFirst().dropLast()
            forms.append(Data(secret.utf8))
            forms.append(Data(json.utf8))
            forms.append(Data(json.replacingOccurrences(of: "/", with: "\\/").utf8))
            forms.append(Data((secret.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? secret).utf8))
            forms.append(secret.data(using: .utf16LittleEndian) ?? Data())
            forms.append(Data(Data(secret.utf8).base64EncodedString().utf8))
        }
        self.forms = Array(Set(forms.filter { $0.count >= 6 }))
    }

    func contains(_ data: Data) -> Bool {
        forms.contains { data.range(of: $0) != nil }
    }

    /// Relative paths of the files holding any form of a secret.
    func search(_ root: URL) -> [String] {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var found: [String] = []
        for case let file as URL in files {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let data = try? Data(contentsOf: file, options: .mappedIfSafe), contains(data) else {
                continue
            }
            found.append(String(file.path.dropFirst(root.path.count)))
        }
        return found
    }
}
