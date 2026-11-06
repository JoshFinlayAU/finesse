import SwiftUI

/// The Settings tab: who is signed in, switching between users on this server, and signing out.
struct AccountView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.jellyfinClient) private var client

    @State private var serverInfo: ServerInfo?
    @State private var isAddingUser = false

    private var currentServer: URL? { app.session?.serverURL }

    var body: some View {
        List {
            Section("Users on This Server") {
                ForEach(app.knownSessions(on: currentServer), id: \.accountKey) { session in
                    Button {
                        if session != app.session {
                            Task { await app.switchUser(to: session) }
                        }
                    } label: {
                        LabeledContent {
                            if session == app.session {
                                Image(systemName: "checkmark")
                            }
                        } label: {
                            Label(session.user.name, systemImage: "person.crop.circle")
                        }
                    }
                    .accessibilityIdentifier("account-\(session.user.name)")
                }
                Button {
                    isAddingUser = true
                } label: {
                    Label("Add User", systemImage: "person.badge.plus")
                }
                .accessibilityIdentifier("addUser")
            }
            Section {
                Button(role: .destructive) {
                    Task { await app.signOut() }
                } label: {
                    Label("Sign Out \(app.session?.user.name ?? "")", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityIdentifier("signOut")
            }
            Section("Server") {
                LabeledContent("Address", value: currentServer?.absoluteString ?? "")
                if let serverInfo {
                    LabeledContent("Name", value: serverInfo.name)
                    LabeledContent("Version", value: serverInfo.version)
                }
            }
        }
        .task { serverInfo = try? await client.serverInfo() }
        .fullScreenCover(isPresented: $isAddingUser) {
            SignInFlowView(app: app, initialServer: currentServer)
        }
        // Choosing the user who is already current changes nothing else, so close the cover here.
        .onChange(of: app.activationCount) {
            isAddingUser = false
        }
    }
}
