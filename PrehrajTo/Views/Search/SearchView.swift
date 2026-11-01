import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @ObservedObject private var library = LibraryManager.shared
    @State private var selectedVideo: VideoItem?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 12) {
                    // Search Input Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)

                        TextField("Hľadať filmy, seriály, dabing...", text: $viewModel.query)
                            .foregroundStyle(.white)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .onSubmit {
                                viewModel.performSearch(resetPage: true)
                            }

                        if !viewModel.query.isEmpty {
                            Button {
                                viewModel.query = ""
                                viewModel.results = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .glassCard(cornerRadius: 14)
                    .padding(.horizontal, 16)

                    // Filter Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SearchFilter.allCases) { filter in
                                let isSelected = viewModel.selectedFilter == filter
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        viewModel.selectedFilter = filter
                                    }
                                } label: {
                                    Text(filter.rawValue)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(isSelected ? .white : .white.opacity(0.75))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(isSelected ? AnyShapeStyle(AppTheme.brandGradient) : AnyShapeStyle(AppTheme.cardBackground))
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Main Content
                    if viewModel.isLoading {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(AppTheme.brandPrimary)
                                .scaleEffect(1.3)
                            Text("Vyhľadávam na Prehraj.to...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    } else if let error = viewModel.errorMessage {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(AppTheme.brandPrimary)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            Button("Skúsiť znova") {
                                viewModel.performSearch(resetPage: true)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.brandPrimary)
                        }
                        .padding(24)
                        Spacer()
                    } else if viewModel.results.isEmpty {
                        emptyOrRecentSearchesView
                    } else {
                        ScrollView {
                            LazyVGrid(columns: gridColumns, spacing: 14) {
                                ForEach(viewModel.filteredResults) { item in
                                    VideoCardView(
                                        item: item,
                                        progress: library.savedProgress(for: item)
                                    ) {
                                        selectedVideo = item
                                    }
                                    .onAppear {
                                        viewModel.loadNextPageIfNeeded(currentItem: item)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)

                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .tint(AppTheme.brandPrimary)
                                    .padding(.vertical, 16)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("Hľadať")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $selectedVideo) { item in
            VideoDetailSheet(item: item)
        }
    }

    private var emptyOrRecentSearchesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !library.recentSearches.isEmpty {
                    HStack {
                        Label("Nedávne vyhľadávania", systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Vymazať") {
                            library.clearRecentSearches()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 8) {
                        ForEach(library.recentSearches, id: \.self) { recent in
                            HStack {
                                Button {
                                    viewModel.query = recent
                                    viewModel.performSearch(resetPage: true)
                                } label: {
                                    HStack {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundStyle(.secondary)
                                        Text(recent)
                                            .foregroundStyle(.white)
                                        Spacer()
                                    }
                                }

                                Button {
                                    library.removeRecentSearch(recent)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .glassCard(cornerRadius: 12)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 46))
                            .foregroundStyle(AppTheme.brandPrimary)
                        Text("Vyhľadajte akékoľvek video")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Zadajte názov filmu, seriálu alebo epizódy (napr. „Duna 2 CZ 1080p“) a prehrajte si ho priamo v natívnom iOS prehrávači.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .glassCard()
                }
            }
            .padding(16)
        }
    }
}
