import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: Int
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var library = LibraryManager.shared

    @State private var featuredVideos: [VideoItem] = []
    @State private var selectedCategoryQuery: String = "CZ dabing 1080p"
    @State private var isLoadingFeatured: Bool = false
    @State private var selectedVideoForSheet: VideoItem?

    private let categories: [DiscoveryCategory] = [
        DiscoveryCategory(
            title: "Filmy CZ/SK",
            subtitle: "Full HD dabing",
            query: "CZ dabing 1080p",
            icon: "film.stack.fill",
            gradientColors: [Color(red: 0.95, green: 0.22, blue: 0.32), Color(red: 0.65, green: 0.12, blue: 0.45)]
        ),
        DiscoveryCategory(
            title: "Seriály",
            subtitle: "Epizódy & série",
            query: "S01E01 CZ",
            icon: "tv.and.mediabox.fill",
            gradientColors: [Color(red: 0.18, green: 0.48, blue: 0.95), Color(red: 0.12, green: 0.22, blue: 0.65)]
        ),
        DiscoveryCategory(
            title: "Rozprávky",
            subtitle: "Pre celú rodinu",
            query: "rozpravka sk dabing",
            icon: "sparkles",
            gradientColors: [Color(red: 0.98, green: 0.56, blue: 0.15), Color(red: 0.85, green: 0.25, blue: 0.20)]
        ),
        DiscoveryCategory(
            title: "Dokumenty",
            subtitle: "Príroda & história",
            query: "dokument cz 1080p",
            icon: "globe.europe.africa.fill",
            gradientColors: [Color(red: 0.12, green: 0.72, blue: 0.52), Color(red: 0.08, green: 0.42, blue: 0.38)]
        )
    ]

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        // Top Brand & Premium Status Header
                        headerBar

                        // Premium Call-to-Action Banner (if not logged in)
                        if !auth.isPremiumActive {
                            premiumPromoBanner
                        }

                        // Continue Watching Section (Rozpozerané)
                        if !library.watchHistory.isEmpty {
                            continueWatchingSection
                        }

                        // Quick Categories
                        categoriesSection

                        // Featured / Category Feed
                        featuredSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .refreshable {
                    await loadCategoryFeed(query: selectedCategoryQuery)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            if featuredVideos.isEmpty {
                await loadCategoryFeed(query: selectedCategoryQuery)
            }
        }
        .sheet(item: $selectedVideoForSheet) { item in
            VideoDetailSheet(item: item)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.brandGradient)
                        .frame(width: 40, height: 40)
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Prehraj.to")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(.white)
                    Text("Natívny iOS prehrávač")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                selectedTab = 4 // Switch to Account tab
            } label: {
                if auth.isPremiumActive {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                        Text("PREMIUM")
                            .font(.caption.weight(.heavy))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AppTheme.premiumGradient, in: Capsule())
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.caption)
                        Text("Pridať Premium")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassCard(cornerRadius: 20)
                }
            }
        }
    }

    // MARK: - Premium Promo Banner

    private var premiumPromoBanner: some View {
        Button {
            selectedTab = 4
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppTheme.premiumGradient)
                        .frame(width: 46, height: 46)
                    Image(systemName: "crown.fill")
                        .font(.title3.bold())
                        .foregroundStyle(.black)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Pripojte svoj Prehraj.to Premium účet")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Odomknite nekomprimovanú Originál kvalitu, 4K streamy a neobmedzené offline sťahovanie.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.premiumGold)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.premiumGold.opacity(0.20),
                                AppTheme.cardBackground
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppTheme.premiumGold.opacity(0.45), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Continue Watching

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Rozpozerané", systemImage: "play.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button("Vymazať") {
                    library.clearHistory()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(library.watchHistory.prefix(10)) { entry in
                        VideoCardView(item: entry.video, progress: entry) {
                            selectedVideoForSheet = entry.video
                        }
                        .frame(width: 220)
                    }
                }
            }
        }
    }

    // MARK: - Categories Section

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rýchly výber kategórií")
                .font(.headline)
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(categories) { category in
                        let isSelected = selectedCategoryQuery == category.query
                        Button {
                            selectedCategoryQuery = category.query
                            Task {
                                await loadCategoryFeed(query: category.query)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: category.icon)
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.title)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                    Text(category.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: isSelected ? category.gradientColors : [AppTheme.cardBackground, AppTheme.cardBackground],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(isSelected ? Color.white.opacity(0.4) : AppTheme.cardBorder, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Featured Feed

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Odporúčané videá")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if isLoadingFeatured {
                    ProgressView()
                        .tint(AppTheme.brandPrimary)
                        .scaleEffect(0.85)
                }
            }

            if featuredVideos.isEmpty && !isLoadingFeatured {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Prejdite do záložky Hľadať a vyhľadajte ľubovoľný film alebo seriál.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .glassCard()
            } else {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(featuredVideos) { item in
                        VideoCardView(
                            item: item,
                            progress: library.savedProgress(for: item)
                        ) {
                            selectedVideoForSheet = item
                        }
                    }
                }
            }
        }
    }

    private func loadCategoryFeed(query: String) async {
        isLoadingFeatured = true
        if let items = try? await PrehrajToClient.shared.search(query: query, page: 1) {
            featuredVideos = items
        }
        isLoadingFeatured = false
    }
}
