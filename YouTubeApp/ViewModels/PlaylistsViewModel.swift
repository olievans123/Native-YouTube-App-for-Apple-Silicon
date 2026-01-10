import Foundation

@MainActor
class PlaylistsViewModel: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var isLoading = true  // Start true to show loading initially
    @Published var isLoadingMore = false
    @Published var error: String?
    @Published var hasAttemptedLoad = false
    @Published var hasMore = true

    private let ytdlp = YTDLPService.shared
    private let pageSize = 20
    private var nextPageStart = 1
    private var countInFlight = Set<String>()

    func loadPlaylists() async {
        print("[PlaylistsVM] Loading playlists...")
        isLoading = true
        error = nil
        hasMore = true
        nextPageStart = 1

        do {
            let newPlaylists = try await ytdlp.fetchPlaylistsRange(
                start: nextPageStart,
                end: nextPageStart + pageSize - 1
            )
            playlists = newPlaylists
            nextPageStart += pageSize
            hasMore = newPlaylists.count >= pageSize
            prefetchCounts(for: newPlaylists)
            print("[PlaylistsVM] Loaded \(playlists.count) playlists")
            for (index, playlist) in playlists.prefix(3).enumerated() {
                print("[PlaylistsVM] Playlist \(index): \(playlist.title) (id: \(playlist.id))")
            }
        } catch {
            self.error = error.localizedDescription
            print("[PlaylistsVM] Error: \(error)")
            hasMore = false
        }

        isLoading = false
        hasAttemptedLoad = true
    }

    func loadMore() async {
        guard !isLoadingMore, hasMore else { return }

        isLoadingMore = true
        do {
            let newPlaylists = try await ytdlp.fetchPlaylistsRange(
                start: nextPageStart,
                end: nextPageStart + pageSize - 1
            )
            _ = appendUniquePlaylists(newPlaylists)
            nextPageStart += pageSize
            hasMore = newPlaylists.count >= pageSize
            prefetchCounts(for: newPlaylists)
        } catch {
            self.error = error.localizedDescription
            print("[PlaylistsVM] Load more error: \(error)")
        }
        isLoadingMore = false
    }

    func refresh() async {
        await loadPlaylists()
    }

    private func appendUniquePlaylists(_ newPlaylists: [Playlist]) -> Bool {
        guard !newPlaylists.isEmpty else { return false }
        var seen = Set(playlists.map(\.id))
        let unique = newPlaylists.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { return false }
        playlists.append(contentsOf: unique)
        return true
    }

    func loadPlaylistCountIfNeeded(for playlist: Playlist) {
        if let count = playlist.videoCount, count > 0 { return }
        guard !countInFlight.contains(playlist.id) else { return }
        countInFlight.insert(playlist.id)

        Task { [weak self] in
            guard let self else { return }
            do {
                let count = try await ytdlp.fetchPlaylistCount(playlistId: playlist.id)
                _ = await MainActor.run {
                    if let count {
                        self.updatePlaylistCount(count, for: playlist.id)
                    }
                    self.countInFlight.remove(playlist.id)
                }
            } catch {
                _ = await MainActor.run {
                    self.countInFlight.remove(playlist.id)
                }
            }
        }
    }

    private func updatePlaylistCount(_ count: Int, for playlistId: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        let playlist = playlists[index]
        playlists[index] = Playlist(
            id: playlist.id,
            title: playlist.title,
            thumbnailURL: playlist.thumbnailURL,
            videoCount: count,
            channel: playlist.channel
        )
    }

    private func prefetchCounts(for playlists: [Playlist], limit: Int = 6) {
        for playlist in playlists.prefix(limit) {
            loadPlaylistCountIfNeeded(for: playlist)
        }
    }
}

@MainActor
class PlaylistDetailViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading = true  // Start as true to show loading state initially
    @Published var isLoadingMore = false
    @Published var error: String?
    @Published var hasMore = true
    @Published var hasAttemptedLoad = false  // Track if we've tried loading
    @Published var totalVideoCount: Int?

    private let ytdlp = YTDLPService.shared
    private var currentPlaylistId: String?
    private let pageSize = 20
    private var nextPageStart = 1
    private var expectedVideoCount: Int?

    func loadVideos(playlistId: String, expectedCount: Int? = nil) async {
        print("[PlaylistDetailVM] Loading videos for playlist: \(playlistId)")
        currentPlaylistId = playlistId
        expectedVideoCount = expectedCount
        totalVideoCount = expectedCount
        isLoading = true
        error = nil
        videos = []
        hasMore = true
        nextPageStart = 1

        let targetPlaylistId = playlistId
        Task { [weak self] in
            guard let self else { return }
            do {
                let count = try await ytdlp.fetchPlaylistCount(playlistId: targetPlaylistId)
                _ = await MainActor.run {
                    guard self.currentPlaylistId == targetPlaylistId else { return }
                    if let count {
                        self.totalVideoCount = count
                        self.expectedVideoCount = count
                        if self.videos.count >= count {
                            self.hasMore = false
                        }
                    }
                }
            } catch {
                // Ignore count errors; we can still page by batches.
            }
        }

        do {
            let newVideos = try await ytdlp.fetchPlaylistVideosRange(
                playlistId: playlistId,
                start: nextPageStart,
                end: nextPageStart + pageSize - 1
            )
            if newVideos.isEmpty {
                let expanded = try await ytdlp.fetchPlaylistVideos(
                    playlistId: playlistId,
                    limit: nextPageStart + pageSize - 1
                )
                videos = expanded
                nextPageStart = expanded.count + 1
                updateHasMore(lastBatchCount: expanded.count)
            } else {
                videos = newVideos
                nextPageStart += pageSize
                updateHasMore(lastBatchCount: newVideos.count)
            }
            print("[PlaylistDetailVM] Successfully loaded \(videos.count) videos")
            for (index, video) in videos.prefix(3).enumerated() {
                print("[PlaylistDetailVM] Video \(index): \(video.title) (id: \(video.id))")
            }
        } catch let ytdlpError as YTDLPError {
            self.error = "Failed to load videos: \(ytdlpError)"
            print("[PlaylistDetailVM] YTDLPError: \(ytdlpError)")
        } catch {
            self.error = error.localizedDescription
            print("[PlaylistDetailVM] Error: \(error)")
        }

        isLoading = false
        hasAttemptedLoad = true
    }

    func loadMore() async {
        guard let playlistId = currentPlaylistId, !isLoadingMore, hasMore else { return }

        isLoadingMore = true
        let startIndex = nextPageStart
        let endIndex = nextPageStart + pageSize - 1
        let previousCount = videos.count

        do {
            let newVideos = try await ytdlp.fetchPlaylistVideosRange(
                playlistId: playlistId,
                start: startIndex,
                end: endIndex
            )
            if newVideos.isEmpty {
                let expanded = try await ytdlp.fetchPlaylistVideos(
                    playlistId: playlistId,
                    limit: endIndex
                )
                if expanded.count > previousCount {
                    videos = expanded
                }
                let delta = max(0, videos.count - previousCount)
                nextPageStart = videos.count + 1
                updateHasMore(lastBatchCount: delta)
                print("Loaded \(delta) more videos, total: \(videos.count)")
            } else {
                videos.append(contentsOf: newVideos)
                nextPageStart = endIndex + 1
                updateHasMore(lastBatchCount: newVideos.count)
                print("Loaded \(newVideos.count) more videos, total: \(videos.count)")
            }
        } catch {
            print("Load more error: \(error)")
        }

        isLoadingMore = false
    }

    private func updateHasMore(lastBatchCount: Int) {
        if lastBatchCount == 0 {
            hasMore = false
            return
        }

        if let expectedVideoCount, expectedVideoCount > videos.count {
            hasMore = nextPageStart <= expectedVideoCount
        } else {
            hasMore = true
        }
    }
}
