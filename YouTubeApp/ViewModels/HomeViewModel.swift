import Foundation

@MainActor
class HomeViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?
    @Published var hasMore = true

    private let ytdlp = YTDLPService.shared
    private let pageSize = 30
    private var nextPageStart = 1

    func loadVideos() async {
        isLoading = true
        error = nil
        hasMore = true
        nextPageStart = 1

        do {
            let newVideos = try await ytdlp.fetchHomeFeedRange(
                start: nextPageStart,
                end: nextPageStart + pageSize - 1
            )
            videos = newVideos
            nextPageStart += pageSize
            hasMore = !newVideos.isEmpty
        } catch {
            self.error = error.localizedDescription
            hasMore = false
        }

        isLoading = false
    }

    func loadMore() async {
        guard !isLoadingMore, hasMore else { return }

        isLoadingMore = true
        do {
            let newVideos = try await ytdlp.fetchHomeFeedRange(
                start: nextPageStart,
                end: nextPageStart + pageSize - 1
            )
            _ = appendUniqueVideos(newVideos)
            nextPageStart += pageSize
            hasMore = !newVideos.isEmpty
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingMore = false
    }

    func refresh() async {
        await loadVideos()
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
