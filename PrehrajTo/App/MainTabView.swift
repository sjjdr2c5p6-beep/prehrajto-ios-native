import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int = 0
    @ObservedObject private var downloads = DownloadManager.shared
    @ObservedObject private var auth = AuthManager.shared

    var activeDownloadsCount: Int {
        downloads.downloads.filter { $0.state == .downloading }.count
    }

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 0.88)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Domov", systemImage: "play.house.fill")
                }
                .tag(0)

            SearchView()
                .tabItem {
                    Label("Hľadať", systemImage: "magnifyingglass")
                }
                .tag(1)

            DownloadsView()
                .tabItem {
                    Label("Stiahnuté", systemImage: "arrow.down.circle.fill")
                }
                .badge(activeDownloadsCount > 0 ? activeDownloadsCount : 0)
                .tag(2)

            LibraryView()
                .tabItem {
                    Label("Knižnica", systemImage: "heart.rectangle.fill")
                }
                .tag(3)

            AccountView()
                .tabItem {
                    Label(auth.isPremiumActive ? "Premium ★" : "Premium", systemImage: "crown.fill")
                }
                .tag(4)
        }
        .tint(AppTheme.brandPrimary)
        .preferredColorScheme(.dark)
    }
}
