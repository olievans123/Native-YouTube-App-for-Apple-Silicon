import Foundation
import AVKit
import Combine
import os.log

private let logger = Logger(subsystem: "com.youtubeapp", category: "PlayerViewModel")

@MainActor
class PlayerViewModel: ObservableObject {
    @Published var currentVideo: Video?
    @Published var isLoading = false
    @Published var error: String?
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var selectedFormat: VideoFormatOption
    @Published var availableFormats: [VideoFormatOption] = [.auto]
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var theaterRequested = false
    @Published var statusMessage: String?
    @Published var activeQualityLabel: String = "Auto"
    @Published var pendingQualityLabel: String?
    private var pendingQualityItemId: ObjectIdentifier?

    // Playlist queue
    @Published var playlistQueue: [Video] = []
    @Published var currentQueueIndex: Int = 0
    @Published var isAutoPlayEnabled: Bool = true

    var hasNextVideo: Bool { !playlistQueue.isEmpty && currentQueueIndex < playlistQueue.count - 1 }
    var hasPreviousVideo: Bool { !playlistQueue.isEmpty && currentQueueIndex > 0 }
    var queuePosition: String? {
        guard !playlistQueue.isEmpty else { return nil }
        return "\(currentQueueIndex + 1)/\(playlistQueue.count)"
    }
    var displayQualityLabel: String {
        if let pendingQualityLabel,
           pendingQualityLabel != activeQualityLabel {
            return "\(activeQualityLabel) >> \(pendingQualityLabel)"
        }
        return activeQualityLabel
    }

    private let ytdlp = YTDLPService.shared
    private let formatCache = FormatCacheService.shared
    private var cancellables = Set<AnyCancellable>()
    private var itemCancellables = Set<AnyCancellable>()
    private var streamCache: [String: StreamURLs] = [:]
    private var playbackToken = UUID()
    private var timeObserverToken: Any?
    private var statusMessageTask: Task<Void, Never>?
    init() {
        selectedFormat = .auto
        setupNotifications()
    }

    func playVideo(
        _ video: Video,
        resumeTime: CMTime? = nil,
        autoPlay: Bool = true,
        formatOverride: VideoFormatOption? = nil
    ) async {
        playbackToken = UUID()
        let token = playbackToken
        let isSameVideo = currentVideo?.id == video.id

        currentVideo = video
        error = nil
        isLoading = true
        if !isSameVideo {
            availableFormats = [.auto]
        }
        let requestedFormat: VideoFormatOption?
        if let formatOverride {
            selectedFormat = formatOverride
            requestedFormat = formatOverride
        } else if !isSameVideo {
            selectedFormat = .auto
            requestedFormat = nil
        } else {
            requestedFormat = selectedFormat.id == VideoFormatOption.auto.id ? nil : selectedFormat
        }

        player?.pause()
        player?.replaceCurrentItem(with: nil)
        isPlaying = false
        currentTime = 0
        duration = 0

        do {
            // Single combined call - gets formats, channel, and stream URLs together
            let (formats, channel, streams) = try await ytdlp.getVideoInfoCombined(
                videoId: video.id,
                requestedFormat: requestedFormat
            )
            guard playbackToken == token else { return }

            // Update formats and channel from the combined response
            availableFormats = formats
            if formats.count > 1 {
                await formatCache.cacheFormats(formats, for: video.id)
            }
            if !formats.contains(where: { $0.id == selectedFormat.id }) {
                selectedFormat = .auto
            }

            // Update channel name if we got one and current video has "Unknown"
            if let channel, currentVideo?.channel == "Unknown" {
                if let video = currentVideo {
                    currentVideo = Video(
                        id: video.id,
                        title: video.title,
                        channel: channel,
                        channelId: video.channelId,
                        thumbnailURL: video.thumbnailURL,
                        duration: video.duration,
                        viewCount: video.viewCount,
                        publishedAt: video.publishedAt
                    )
                }
            }

            // Cache the streams
            let cacheKey = "\(video.id)|\(requestedFormat?.id ?? "auto")"
            streamCache[cacheKey] = streams

            let canFastStart = requestedFormat == nil &&
                streams.hasSeparateStreams &&
                streams.muxedURL != nil

            if canFastStart, let muxedURL = streams.muxedURL {
                activeQualityLabel = "Auto"
                pendingQualityLabel = pendingLabel(for: selectedFormat)
                pendingQualityItemId = nil
                let muxedItem = AVPlayerItem(url: muxedURL)
                startPlayback(
                    with: muxedItem,
                    resumeTime: resumeTime,
                    autoPlay: autoPlay,
                    startImmediately: true,
                    shouldPreload: true
                )

                Task { [weak self] in
                    guard let self else { return }
                    do {
                        let fullItem = try await self.makePlayerItem(from: streams)
                        guard self.playbackToken == token else { return }
                        self.pendingQualityItemId = ObjectIdentifier(fullItem)
                        self.replaceCurrentItemPreservingTime(fullItem)
                    } catch {
                        // Keep the fast-start muxed stream if the upgrade fails.
                    }
                }
                return
            }

            activeQualityLabel = selectedFormat.id == VideoFormatOption.auto.id ? "Auto" : selectedFormat.shortLabel
            pendingQualityLabel = nil
            pendingQualityItemId = nil
            let playerItem = try await makePlayerItem(from: streams)
            guard playbackToken == token else { return }
            startPlayback(
                with: playerItem,
                resumeTime: resumeTime,
                autoPlay: autoPlay,
                startImmediately: false,
                shouldPreload: true
            )
        } catch {
            if playbackToken == token {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func togglePlayback() {
        guard let player = player else { return }

        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    func seek(by seconds: Double) {
        guard let player = player else { return }
        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(currentTime, CMTimeMakeWithSeconds(seconds, preferredTimescale: 1))
        player.seek(to: newTime)
    }

    func seek(to seconds: Double) {
        guard let player = player else { return }
        let time = CMTimeMakeWithSeconds(seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setFormat(_ format: VideoFormatOption) {
        guard format.id != selectedFormat.id else { return }
        selectedFormat = format
        showStatusMessage(formatSwitchMessage(for: format))
        pendingQualityLabel = pendingLabel(for: format)
        pendingQualityItemId = nil

        guard let video = currentVideo else { return }
        Task {
            await switchFormat(video: video, format: format)
        }
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        currentVideo = nil
        isLoading = false
        error = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        activeQualityLabel = "Auto"
        pendingQualityLabel = nil
        pendingQualityItemId = nil
    }

    func requestTheater() {
        theaterRequested = true
    }

    func consumeTheaterRequest() {
        theaterRequested = false
    }

    // MARK: - Playlist Queue

    func playVideoFromPlaylist(_ video: Video, playlist: [Video], startIndex: Int) async {
        playlistQueue = playlist
        currentQueueIndex = startIndex
        await playVideo(video)
    }

    func playNextVideo() async {
        guard hasNextVideo else { return }
        currentQueueIndex += 1
        await playVideo(playlistQueue[currentQueueIndex])
    }

    func playPreviousVideo() async {
        guard hasPreviousVideo else { return }
        currentQueueIndex -= 1
        await playVideo(playlistQueue[currentQueueIndex])
    }

    func clearQueue() {
        playlistQueue = []
        currentQueueIndex = 0
    }

    private func preloadNextVideoInQueue() {
        guard hasNextVideo else { return }
        let nextVideo = playlistQueue[currentQueueIndex + 1]
        let cacheKey = "\(nextVideo.id)|auto"

        // Don't preload if already cached
        guard streamCache[cacheKey] == nil else { return }

        Task.detached(priority: .background) { [ytdlp] in
            do {
                let streams = try await ytdlp.getStreams(videoId: nextVideo.id, format: nil)
                await MainActor.run { [weak self] in
                    self?.streamCache[cacheKey] = streams
                }
            } catch {
                // Silently fail - preloading is best-effort
            }
        }
    }

    private func startPlayback(
        with item: AVPlayerItem,
        resumeTime: CMTime?,
        autoPlay: Bool,
        startImmediately: Bool,
        shouldPreload: Bool
    ) {
        configurePlayerIfNeeded(startImmediately: startImmediately)
        configurePlayerItem(item)
        observePlayerItem(item)

        player?.replaceCurrentItem(with: item)

        if let resumeTime {
            player?.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if autoPlay {
                        self.player?.play()
                        if shouldPreload {
                            self.preloadNextVideoInQueue()
                        }
                    }
                }
            }
        } else if autoPlay {
            player?.play()
            if shouldPreload {
                preloadNextVideoInQueue()
            }
        }
    }

    private func replaceCurrentItemPreservingTime(
        _ item: AVPlayerItem,
        startImmediately: Bool = false
    ) {
        let shouldResume = player?.timeControlStatus == .playing
        let resumeTime = player?.currentTime()

        configurePlayerIfNeeded(startImmediately: startImmediately)
        configurePlayerItem(item)
        observePlayerItem(item)
        player?.replaceCurrentItem(with: item)

        if let resumeTime {
            player?.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in
                    if shouldResume {
                        self?.player?.play()
                    }
                }
            }
        } else if shouldResume {
            player?.play()
        }
    }

    private func configurePlayerIfNeeded(startImmediately: Bool = false) {
        if player == nil {
            let newPlayer = AVPlayer()
            player = newPlayer
            observePlayer(newPlayer)
        }
        player?.automaticallyWaitsToMinimizeStalling = !startImmediately
    }

    private func switchFormat(video: Video, format: VideoFormatOption) async {
        playbackToken = UUID()
        let token = playbackToken
        error = nil

        do {
            pendingQualityLabel = pendingLabel(for: format)
            pendingQualityItemId = nil
            let (formats, channel, streams) = try await ytdlp.getVideoInfoCombined(
                videoId: video.id,
                requestedFormat: format
            )
            guard playbackToken == token else { return }

            availableFormats = formats
            if formats.count > 1 {
                await formatCache.cacheFormats(formats, for: video.id)
            }
            if !formats.contains(where: { $0.id == selectedFormat.id }) {
                selectedFormat = .auto
            }

            if let channel, currentVideo?.channel == "Unknown" {
                if let current = currentVideo {
                    currentVideo = Video(
                        id: current.id,
                        title: current.title,
                        channel: channel,
                        channelId: current.channelId,
                        thumbnailURL: current.thumbnailURL,
                        duration: current.duration,
                        viewCount: current.viewCount,
                        publishedAt: current.publishedAt
                    )
                }
            }

            let cacheKey = "\(video.id)|\(format.id)"
            streamCache[cacheKey] = streams

            let playerItem = try await makePlayerItem(from: streams)
            guard playbackToken == token else { return }

            pendingQualityItemId = ObjectIdentifier(playerItem)
            replaceCurrentItemPreservingTime(playerItem, startImmediately: false)
        } catch {
            if playbackToken == token {
                self.error = error.localizedDescription
                self.pendingQualityLabel = nil
                self.pendingQualityItemId = nil
            }
        }
    }

    private func configurePlayerItem(_ item: AVPlayerItem) {
        item.preferredForwardBufferDuration = 6
    }

    private func observePlayer(_ player: AVPlayer) {
        setupTimeObserver(player)

        player.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch status {
                    case .waitingToPlayAtSpecifiedRate:
                        self.isLoading = true
                        self.isPlaying = false
                    case .playing:
                        self.isLoading = false
                        self.isPlaying = true
                    case .paused:
                        self.isLoading = false
                        self.isPlaying = false
                    @unknown default:
                        break
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func setupTimeObserver(_ player: AVPlayer) {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            if seconds.isFinite {
                Task { @MainActor [weak self] in
                    self?.currentTime = seconds
                }
            }
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        itemCancellables.removeAll()

        item.publisher(for: \.status)
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if status == .failed {
                        self.error = item.error?.localizedDescription ?? "Playback failed"
                        self.isLoading = false
                        self.isPlaying = false
                    } else if status == .readyToPlay {
                        let itemDuration = item.duration.seconds
                        if itemDuration.isFinite {
                            self.duration = itemDuration
                        }
                        self.currentTime = 0
                        self.updateActiveQualityLabel(for: item)
                        if let pendingId = self.pendingQualityItemId,
                           ObjectIdentifier(item) == pendingId {
                            self.pendingQualityLabel = nil
                            self.pendingQualityItemId = nil
                        }
                    }
                }
            }
            .store(in: &itemCancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isPlaying = false

                    // Auto-play next video in queue
                    if self.isAutoPlayEnabled && self.hasNextVideo {
                        await self.playNextVideo()
                    }
                }
            }
            .store(in: &itemCancellables)
    }

    private func makePlayerItem(from streams: StreamURLs) async throws -> AVPlayerItem {
        if streams.hasSeparateStreams,
           let videoURL = streams.videoURL,
           let audioURL = streams.audioURL {
            let videoAsset = AVURLAsset(url: videoURL)
            let audioAsset = AVURLAsset(url: audioURL)

            let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
            let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)

            guard let videoTrack = videoTracks.first,
                  let audioTrack = audioTracks.first else {
                throw PlayerError.missingTracks
            }

            let composition = AVMutableComposition()
            guard let videoCompTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let audioCompTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw PlayerError.compositionFailed
            }

            let videoDuration = try await videoAsset.load(.duration)
            let audioDuration = try await audioAsset.load(.duration)
            let duration = minDuration(videoDuration, audioDuration)

            let timeRange = CMTimeRange(start: .zero, duration: duration)
            try videoCompTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
            try audioCompTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)

            return AVPlayerItem(asset: composition)
        }

        if let muxedURL = streams.muxedURL {
            return AVPlayerItem(url: muxedURL)
        }

        throw PlayerError.noPlayableStream
    }

    private func minDuration(_ first: CMTime, _ second: CMTime) -> CMTime {
        if first.isIndefinite || !first.isValid {
            return second
        }
        if second.isIndefinite || !second.isValid {
            return first
        }
        return CMTimeCompare(first, second) <= 0 ? first : second
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .togglePlayback)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.togglePlayback()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .playNextVideo)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.playNextVideo()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .playPreviousVideo)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.playPreviousVideo()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .seekForward)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.seek(by: 10)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .seekBackward)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.seek(by: -10)
                }
            }
            .store(in: &cancellables)
    }

    private func showStatusMessage(_ message: String) {
        statusMessageTask?.cancel()
        statusMessage = message
        statusMessageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                self?.statusMessage = nil
            }
        }
    }

    private func formatSwitchMessage(for format: VideoFormatOption) -> String {
        if format.id == VideoFormatOption.auto.id {
            return "Switching to Auto (best available)"
        }
        return "Switching to \(format.shortLabel) when available"
    }

    private func pendingLabel(for format: VideoFormatOption) -> String {
        if format.id == VideoFormatOption.auto.id {
            let explicitFormats = availableFormats.filter { $0.id != VideoFormatOption.auto.id }
            let bestAvailable = explicitFormats.max { lhs, rhs in
                let lhsHeight = lhs.height ?? 0
                let rhsHeight = rhs.height ?? 0
                if lhsHeight != rhsHeight { return lhsHeight < rhsHeight }
                let lhsFps = Int(lhs.fps?.rounded() ?? 0)
                let rhsFps = Int(rhs.fps?.rounded() ?? 0)
                return lhsFps < rhsFps
            }
            return bestAvailable?.shortLabel ?? "Auto"
        }

        return format.shortLabel
    }

    private func updateActiveQualityLabel(for item: AVPlayerItem) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let tracks = try await item.asset.loadTracks(withMediaType: .video)
                guard let track = tracks.first else { return }
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let height = Int(abs(size.applying(transform).height).rounded())
                guard height > 0 else { return }
                await MainActor.run {
                    self.activeQualityLabel = "\(height)p"
                }
            } catch {
                // Ignore; keep the last known quality label.
            }
        }
    }

}

enum PlayerError: LocalizedError {
    case noPlayableStream
    case missingTracks
    case compositionFailed

    var errorDescription: String? {
        switch self {
        case .noPlayableStream:
            return "No playable stream available"
        case .missingTracks:
            return "Missing video or audio tracks"
        case .compositionFailed:
            return "Failed to build playback composition"
        }
    }
}
