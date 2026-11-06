import SwiftUI

struct SignInFlowView: View {
    @State private var model: SignInModel
    private let connectsAutomatically: Bool

    init(app: AppModel, initialServer: URL?) {
        _model = State(initialValue: SignInModel(app: app, initialServer: initialServer))
        connectsAutomatically = initialServer != nil
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            ServerEntryView(model: model)
                .navigationDestination(for: SignInModel.Step.self) { step in
                    switch step {
                    case .users:
                        UserPickerView(model: model)
                    case .password(let username):
                        CredentialsView(model: model, username: username)
                    case .otherUser:
                        CredentialsView(model: model, username: nil)
                    case .quickConnect:
                        QuickConnectView(model: model)
                    }
                }
        }
        .task {
            if connectsAutomatically { await model.connect() }
        }
    }
}

/// The shared layout of each sign-in step: heading, explanation, then the step's controls.
private struct SignInPage<Content: View>: View {
    let title: String
    var message: String?
    var errorMessage: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 16) {
                Text(title)
                    .font(.title)
                    .fontWeight(.semibold)
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            content()
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("signInError")
            }
        }
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ServerEntryView: View {
    let model: SignInModel

    var body: some View {
        @Bindable var model = model
        SignInPage(
            title: "Connect to Your Server",
            message: "Enter the address of your Jellyfin server.",
            errorMessage: model.errorMessage
        ) {
            TextField("Server address, such as 192.168.1.20:8096", text: $model.serverAddress)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("serverAddress")
                .onSubmit { Task { await model.connect() } }
            Button {
                Task { await model.connect() }
            } label: {
                Text(model.isBusy ? "Connecting..." : "Continue")
                    .frame(minWidth: 400)
            }
            .disabled(model.isBusy || model.serverAddress.isEmpty)
            .accessibilityIdentifier("connect")
        }
    }
}

private struct UserPickerView: View {
    let model: SignInModel

    var body: some View {
        SignInPage(
            title: "Who's Watching?",
            message: model.serverInfo?.name,
            errorMessage: model.errorMessage
        ) {
            List {
                Section {
                    ForEach(model.userChoices) { choice in
                        Button {
                            Task { await model.choose(choice) }
                        } label: {
                            Label(choice.name, systemImage: "person.crop.circle")
                        }
                        .accessibilityIdentifier("user-\(choice.name)")
                    }
                }
                Section {
                    NavigationLink(value: SignInModel.Step.otherUser) {
                        Label("Other User", systemImage: "person.badge.plus")
                    }
                    .accessibilityIdentifier("otherUser")
                    if model.quickConnectAvailable {
                        NavigationLink(value: SignInModel.Step.quickConnect) {
                            Label("Quick Connect", systemImage: "qrcode")
                        }
                        .accessibilityIdentifier("quickConnect")
                    }
                }
            }
        }
        .onAppear { model.clearError() }
    }
}

/// Asks for a password, and also for a username when the user isn't listed by the server.
private struct CredentialsView: View {
    let model: SignInModel
    let username: String?

    @State private var typedUsername = ""
    @State private var password = ""

    private var effectiveUsername: String { username ?? typedUsername }

    var body: some View {
        SignInPage(
            title: username ?? "Sign In",
            message: username == nil ? "Enter your username and password." : "Enter your password.",
            errorMessage: model.errorMessage
        ) {
            if username == nil {
                TextField("Username", text: $typedUsername)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("username")
            }
            SecureField("Password", text: $password)
                .textContentType(.password)
                .accessibilityIdentifier("password")
            Button {
                Task { await model.signIn(username: effectiveUsername, password: password) }
            } label: {
                Text(model.isBusy ? "Signing In..." : "Sign In")
                    .frame(minWidth: 400)
            }
            .disabled(model.isBusy || effectiveUsername.isEmpty)
            .accessibilityIdentifier("signIn")
        }
        .onAppear { model.clearError() }
    }
}

private struct QuickConnectView: View {
    let model: SignInModel
    @State private var attempt = 0

    var body: some View {
        SignInPage(
            title: "Quick Connect",
            message: "On a device already signed in, open Quick Connect in your user settings and enter this code.",
            errorMessage: model.errorMessage
        ) {
            if let code = model.quickConnectCode {
                Text(code)
                    .font(.system(size: 96, weight: .semibold, design: .monospaced))
                    .accessibilityIdentifier("quickConnectCode")
                ProgressView()
            } else if model.errorMessage != nil {
                Button("Try Again") { attempt += 1 }
            } else {
                ProgressView()
            }
        }
        .focusable(model.quickConnectCode != nil)
        .task(id: attempt) { await model.runQuickConnect() }
    }
}
