import Foundation
import SwiftUI

@MainActor
final class LibraryManager: ObservableObject {
    static let shared = LibraryManager()

    @Published private(set) var watchHistory: [WatchProgressItem] = []
    @Published private(set) var favorites: [VideoItem] = []
    @Published private(set) var recentSearches: [String] = []

    private let historyKey = "prehrajto_watch_history"
    private let favoritesKey = "prehrajto_favorites"
    private let recentSearchesKey = "prehrajto_recent_searches"

    init() {
        loadAll()
    }

    // MARK: - Watch Progress / Resume

    func updateProgress(for video: VideoItem, currentTime: Double, duration: Double, qualityLabel: String?) {
        guard duration > 5, currentTime >= 2 else { return }

        var list = watchHistory
        list.removeAll { $0.video.id == video.id }

        // If user watched > 96%, we can still store it in history or mark near end
        let item = WatchProgressItem(
            video: video,
            currentTime: currentTime,
            duration: duration,
            lastWatchedAt: Date(),
            selectedQualityLabel: qualityLabel
        )
        list.insert(item, at: 0)

        if list.count > 60 {
            list = Array(list.prefix(60))
        }

        watchHistory = list
        saveHistory()
    }

    func savedProgress(for video: VideoItem) -> WatchProgressItem? {
        watchHistory.first { $0.video.id == video.id }
    }

    func removeProgress(for videoId: String) {
        watchHistory.removeAll { $0.id == videoId }
        saveHistory()
    }

    func clearHistory() {
        watchHistory.removeAll()
        saveHistory()
    }

    // MARK: - Favorites

    func isFavorite(_ video: VideoItem) -> Bool {
        favorites.contains { $0.id == video.id }
    }

    func toggleFavorite(_ video: VideoItem) {
        if let index = favorites.firstIndex(where: { $0.id == video.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(video, at: 0)
        }
        saveFavorites()
    }

    // MARK: - Recent Searches

    func addRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 12 {
            recentSearches = Array(recentSearches.prefix(12))
        }
        UserDefaults.standard.set(recentSearches, forKey: recentSearchesKey)
    }

    func removeRecentSearch(_ query: String) {
        recentSearches.removeAll { $0 == query }
        UserDefaults.standard.set(recentSearches, forKey: recentSearchesKey)
    }

    func clearRecentSearches() {
        recentSearches.removeAll()
        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
    }

    // MARK: - Persistence

    private func loadAll() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([WatchProgressItem].self, from: data) {
            watchHistory = decoded
        }
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([VideoItem].self, from: data) {
            favorites = decoded
        }
        if let savedSearches = UserDefaults.standard.stringArray(forKey: recentSearchesKey) {
            recentSearches = savedSearches
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(watchHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }
}
