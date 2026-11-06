import SwiftUI

@main
struct FinesseApp: App {
    @State private var app = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task { app.restore() }
        }
    }
}
