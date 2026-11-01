import SwiftUI

@main
struct PrehrajToApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .task {
                    await AuthManager.shared.refreshSessionIfNeeded()
                }
        }
    }
}
