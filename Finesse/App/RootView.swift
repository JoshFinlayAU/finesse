import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.phase {
        case .launching:
            LoadingStateView()
        case .signedOut:
            SignInFlowView(app: app, initialServer: app.accounts.lastServerURL)
                .id(app.signInAttempt)
        case .signedIn:
            if let client = app.client, let session = app.session {
                MainTabView()
                    .id(session.accountKey)
                    .environment(\.jellyfinClient, client)
            }
        }
    }
}

extension EnvironmentValues {
    /// The signed-in user's client. Outside the signed-in shell this is an empty fake, which suits previews.
    @Entry var jellyfinClient: any JellyfinClient = InMemoryJellyfinClient()
}
