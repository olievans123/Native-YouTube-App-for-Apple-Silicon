import Foundation
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var videos: [Video] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?
    @Published var hasSearched = false
    @Published var hasMore = false

    private let ytdlp = YTDLPService.shared
    private var searchTask: Task<Void, Never>?
    private let pageSize = 20
    private var currentLimit = 0
    private var currentQuery = ""
    private var requestToken = UUID()

    func search() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        searchTask?.cancel()

        isLoading = true
        isLoadingMore = false
        error = nil
        hasSearched = true
        hasMore = true
        currentQuery = trimmedQuery
        currentLimit = pageSize
        videos = []
        let token = UUID()
        requestToken = token

        searchTask = Task {
            do {
                let results = try await ytdlp.search(query: trimmedQuery, limit: currentLimit)
                if !Task.isCancelled, requestToken == token {
                    videos = results
                    hasMore = results.count >= currentLimit
                }
            } catch {
                if !Task.isCancelled, requestToken == token {
                    self.error = error.localizedDescription
                    hasMore = false
                }
            }

            if !Task.isCancelled, requestToken == token {
                isLoading = false
            }
        }
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, hasMore, !currentQuery.isEmpty else { return }

        isLoadingMore = true
        let token = requestToken
        let nextLimit = currentLimit + pageSize

        do {
            let results = try await ytdlp.search(query: currentQuery, limit: nextLimit)
            if !Task.isCancelled, requestToken == token {
                _ = appendUniqueVideos(results)
                currentLimit = nextLimit
                hasMore = results.count >= nextLimit
            }
        } catch {
            // Best-effort paging; keep existing results on failure.
        }

        if !Task.isCancelled, requestToken == token {
            isLoadingMore = false
        }
    }

    func clear() {
        searchTask?.cancel()
        query = ""
        videos = []
        hasSearched = false
        error = nil
        isLoading = false
        isLoadingMore = false
        hasMore = false
        currentLimit = 0
        currentQuery = ""
    }

    private func appendUniqueVideos(_ newVideos: [Video]) -> Bool {
        guard !newVideos.isEmpty else { return false }
        var seen = Set(videos.map(\.id))
        let unique = newVideos.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { return false }
        videos.append(contentsOf: unique)
        return true
    }
}
