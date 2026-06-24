import SwiftUI

@main
struct XueApp: App {
    @StateObject private var auth = AuthSession.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.bootstrapping {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        ProgressView().tint(.white)
                    }
                } else if auth.isAuthenticated {
                    ContentView()
                } else {
                    AuthGateView()
                }
            }
            .task { await auth.bootstrap() }
        }
    }
}

