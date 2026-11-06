import Foundation
import Observation

/// Drives sign-in: server address, then choosing a user, then a password or Quick Connect.
@Observable
@MainActor
final class SignInModel {
    enum Step: Hashable {
        case users
        case password(username: String)
        case otherUser
        case quickConnect
    }

    /// One row on the user picker. A held session signs in with no password.
    enum UserChoice: Identifiable, Hashable {
        case known(UserSession)
        case publicUser(PublicUser)

        var id: String {
            switch self {
            case .known(let session): "known/\(session.user.id)"
            case .publicUser(let user): "public/\(user.id)"
            }
        }

        var name: String {
            switch self {
            case .known(let session): session.user.name
            case .publicUser(let user): user.name
            }
        }
    }

    var path: [Step] = []
    var serverAddress = ""
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var serverInfo: ServerInfo?
    private(set) var userChoices: [UserChoice] = []
    private(set) var quickConnectAvailable = false
    private(set) var quickConnectCode: String?

    private let app: AppModel
    private let quickConnectInterval: Duration
    private var client: (any JellyfinClient)?

    init(app: AppModel, initialServer: URL? = nil, quickConnectInterval: Duration = .seconds(5)) {
        self.app = app
        self.quickConnectInterval = quickConnectInterval
        serverAddress = initialServer?.absoluteString ?? ""
    }

    func clearError() {
        errorMessage = nil
    }

    /// Checks the address really is a Jellyfin server before moving on to choosing a user.
    func connect() async {
        guard let url = ServerAddress.normalize(serverAddress) else {
            errorMessage = JellyfinError.invalidServerURL.userMessage
            return
        }
        await perform {
            let client = app.makeClient(url, app.identity)
            let info = try await client.serverInfo()
            let publicUsers = (try? await client.publicUsers()) ?? []
            let quickConnect = (try? await client.isQuickConnectEnabled()) ?? false

            self.client = client
            serverInfo = info
            quickConnectAvailable = quickConnect
            let known = app.knownSessions(on: url)
            let knownIDs = Set(known.map(\.user.id))
            userChoices = known.map(UserChoice.known)
                + publicUsers.filter { !knownIDs.contains($0.id) }.map(UserChoice.publicUser)
            path = [.users]
        }
    }

    func choose(_ choice: UserChoice) async {
        switch choice {
        case .known(let session):
            await app.switchUser(to: session)
        case .publicUser(let user) where user.hasPassword:
            errorMessage = nil
            path.append(.password(username: user.name))
        case .publicUser(let user):
            await signIn(username: user.name, password: "")
        }
    }

    func signIn(username: String, password: String) async {
        guard let client else { return }
        await perform {
            let session = try await client.signIn(username: username, password: password)
            await app.completeSignIn(session, client: client)
        }
    }

    /// Shows a code and waits for the user to approve it elsewhere. Cancelled by leaving the screen.
    func runQuickConnect() async {
        guard let client else { return }
        errorMessage = nil
        quickConnectCode = nil
        do {
            var request = try await client.startQuickConnect()
            quickConnectCode = request.code
            while !request.isAuthenticated {
                try await Task.sleep(for: quickConnectInterval)
                request = try await client.quickConnectStatus(request)
            }
            let session = try await client.signIn(quickConnect: request)
            await app.completeSignIn(session, client: client)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            quickConnectCode = nil
            errorMessage = error.userMessage
        }
    }

    private func perform(_ work: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            errorMessage = error.userMessage
        }
    }
}
