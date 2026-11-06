import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        content
            .alert(
                "Couldn't Open That",
                isPresented: Binding(get: { app.linkError != nil }, set: { if !$0 { app.linkError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(app.linkError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
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
