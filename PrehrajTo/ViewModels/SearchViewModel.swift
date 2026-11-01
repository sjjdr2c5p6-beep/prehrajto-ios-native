import Foundation
import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [VideoItem] = []
    @Published var selectedFilter: SearchFilter = .all
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var errorMessage: String?
    @Published var currentPage: Int = 1
    @Published var canLoadMore: Bool = false

    private var searchTask: Task<Void, Never>?

    var filteredResults: [VideoItem] {
        switch selectedFilter {
        case .all:
            return results
        case .hdOnly:
            return results.filter { $0.isHD }
        case .largeFiles:
            return results.filter { item in
                let lower = item.fileSize.lowercased().replacingOccurrences(of: ",", with: ".")
                guard lower.contains("gb") else { return false }
                let numeric = lower.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).joined()
                if let sizeGB = Double(numeric) {
                    return sizeGB >= 1.5
                }
                return false
            }
        case .czSk:
            return results.filter { item in
                let title = item.title.lowercased()
                return title.contains("cz")
                    || title.contains("sk")
                    || title.contains("dabing")
                    || title.contains("titulky")
            }
        }
    }

    func performSearch(resetPage: Bool = true) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            errorMessage = nil
            return
        }

        searchTask?.cancel()
        searchTask = Task {
            if resetPage {
                isLoading = true
                currentPage = 1
                errorMessage = nil
            } else {
                isLoadingMore = true
            }

            do {
                let fetched = try await PrehrajToClient.shared.search(query: trimmed, page: currentPage)
                guard !Task.isCancelled else { return }

                if resetPage {
                    results = fetched
                    LibraryManager.shared.addRecentSearch(trimmed)
                } else {
                    let existingIds = Set(results.map(\.id))
                    let uniqueNew = fetched.filter { !existingIds.contains($0.id) }
                    results.append(contentsOf: uniqueNew)
                }
                canLoadMore = fetched.count >= 12
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }

            isLoading = false
            isLoadingMore = false
        }
    }

    func loadNextPageIfNeeded(currentItem: VideoItem) {
        guard !isLoading, !isLoadingMore, canLoadMore else { return }
        guard let lastItem = filteredResults.last, lastItem.id == currentItem.id else { return }
        currentPage += 1
        performSearch(resetPage: false)
    }
}
