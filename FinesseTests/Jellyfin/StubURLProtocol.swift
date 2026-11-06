import Foundation
import Synchronization
import Testing

/// Serves canned responses in place of the network. Only `LiveJellyfinClientTests` uses it, and
/// that suite is serialized, so one handler at a time is enough.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply {
        case response(status: Int, body: Data)
        case failure(Error)
    }

    struct Recorded {
        var request: URLRequest
        var body: Data?
    }

    private struct State {
        var handler: (@Sendable (URLRequest) -> Reply)?
        var recorded: [Recorded] = []
    }

    private static let state = Mutex(State())

    static func reset(handler: @escaping @Sendable (URLRequest) -> Reply) {
        state.withLock { $0 = State(handler: handler) }
    }

    static var recorded: [Recorded] {
        state.withLock { $0.recorded }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let handler = Self.state.withLock { state in
            state.recorded.append(Recorded(request: request, body: body))
            return state.handler
        }
        switch handler?(request) ?? .response(status: 500, body: Data()) {
        case .response(let status, let data):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private static func read(_ stream: InputStream) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        stream.open()
        defer { stream.close() }
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class FixtureBundleToken {}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: FixtureBundleToken.self)
        let url = try #require(bundle.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    /// A fixture with some of its top-level or first-MediaSource values replaced.
    static func json(_ name: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data(name)) as? [String: Any])
    }
}
