import SwiftUI

@main
struct XueApp: App {
    @StateObject private var auth = AuthSession.shared
    @AppStorage("xue.onboarded") private var onboarded = false

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
                        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
                            OnboardingView { onboarded = true }
                        }
                } else {
                    AuthGateView()
                }
            }
            .task { await auth.bootstrap() }
        }
    }
}

