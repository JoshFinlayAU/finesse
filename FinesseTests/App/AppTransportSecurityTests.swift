import Foundation
import Testing

struct AppTransportSecurityTests {
    /// Self-hosted servers are user-configured and often plain HTTP. `NSAllowsLocalNetworking` has to
    /// stay out as well, because when it's present the system ignores `NSAllowsArbitraryLoads`.
    @Test func plainHTTPIsAllowedToAnyServer() throws {
        let settings = try #require(Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any])
        #expect(settings["NSAllowsArbitraryLoads"] as? Bool == true)
        #expect(settings["NSAllowsLocalNetworking"] == nil)
    }
}
