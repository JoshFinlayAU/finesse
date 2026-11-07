import SwiftUI

@main
struct FinesseApp: App {
    @State private var app = AppModel.live()

    init() {
        LiveJellyfinClient.keepSharedResponsesOffDisk()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task { await app.restore() }
                .onOpenURL { url in
                    Task { await app.open(url) }
                }
        }
    }
}
