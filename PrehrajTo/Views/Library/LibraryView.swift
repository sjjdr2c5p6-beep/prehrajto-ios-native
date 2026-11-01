import SwiftUI

struct LibraryView: View {
    @ObservedObject private var library = LibraryManager.shared
    @State private var sectionIndex: Int = 0
    @State private var selectedVideo: VideoItem?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 14) {
                    Picker("Knižnica", selection: $sectionIndex) {
                        Text("Obľúbené (\(library.favorites.count))").tag(0)
                        Text("História (\(library.watchHistory.count))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if sectionIndex == 0 {
                        favoritesContent
                    } else {
                        historyContent
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("Knižnica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if sectionIndex == 1 && !library.watchHistory.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Vymazať") {
                            library.clearHistory()
                        }
                        .font(.caption)
                        .foregroundStyle(AppTheme.brandPrimary)
                    }
                }
            }
        }
        .sheet(item: $selectedVideo) { item in
            VideoDetailSheet(item: item)
        }
    }

    @ViewBuilder
    private var favoritesContent: some View {
        if library.favorites.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "heart.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Zatiaľ žiadne obľúbené videá")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Klepnite na ikonu srdiečka pri videu alebo v prehrávači a uložte si ho sem.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(library.favorites) { item in
                        VideoCardView(
                            item: item,
                            progress: library.savedProgress(for: item)
                        ) {
                            selectedVideo = item
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if library.watchHistory.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("História pozerania je prázdna")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Rozpozerané filmy a seriály sa tu automaticky uložia spolu s časom, kde ste skončili.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(library.watchHistory) { progress in
                        VideoCardView(item: progress.video, progress: progress) {
                            selectedVideo = progress.video
                        }
                    }
                }
                .padding(16)
            }
        }
    }
}
