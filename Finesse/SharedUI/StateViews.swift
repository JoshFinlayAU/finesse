import SwiftUI

struct LoadingStateView: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let title: String
    var message: String?
    var systemImage = "tray"

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message {
                Text(message)
            }
        }
    }
}

/// Shows a failure. The retry button takes focus, so the remote is never left with nothing to do.
struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Try Again", action: retry)
            }
        }
    }
}

extension Error {
    /// Wording for people, safe to show on screen.
    var userMessage: String {
        guard let error = self as? JellyfinError else {
            return "Check the server is reachable and try again."
        }
        switch error {
        case .invalidServerURL:
            return "That doesn't look like a server address."
        case .notAJellyfinServer:
            return "That address didn't answer as a Jellyfin server."
        case .notSignedIn:
            return "You've been signed out. Sign in again."
        case .invalidCredentials:
            return "Incorrect username or password."
        case .forbidden:
            return "This user isn't allowed to do that."
        case .notFound:
            return "That item is no longer on the server."
        case .quickConnectDisabled:
            return "Quick Connect is turned off on this server."
        case .insecureConnectionBlocked:
            return "This address can't be used over plain HTTP. Use HTTPS, or your server's local IP address."
        case .server(let status):
            return "The server reported an error (\(status))."
        case .network:
            return "Couldn't reach the server. Check the address and your network."
        case .decoding:
            return "The server sent something unexpected. Check its version."
        }
    }

    /// True when the stored token no longer works, so the user has to sign in again.
    var isSessionExpired: Bool {
        (self as? JellyfinError) == .notSignedIn
    }
}
