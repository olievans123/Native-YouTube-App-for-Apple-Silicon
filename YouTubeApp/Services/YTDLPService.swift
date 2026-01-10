import Foundation
import os.log

private let logger = Logger(subsystem: "com.youtubeapp", category: "YTDLPService")

private final class OutputBuffer {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func value() -> Data {
        lock.lock()
        let current = data
        lock.unlock()
        return current
    }
}

struct StreamURLs {
    let videoURL: URL?
    let audioURL: URL?
    let muxedURL: URL?

    var hasSeparateStreams: Bool {
        videoURL != nil && audioURL != nil
    }
}

actor YTDLPService {
    static let shared = YTDLPService()

    private let ytdlpPath: String
    private let browserOverride: CookiesBrowser?

    init(ytdlpPath: String = "/opt/homebrew/bin/yt-dlp", browserOverride: CookiesBrowser? = nil) {
        self.ytdlpPath = ytdlpPath
        self.browserOverride = browserOverride
    }

    // MARK: - Public Methods

    func fetchHomeFeed(limit: Int = 30) async throws -> [Video] {
        return try await fetchHomeFeedRange(start: 1, end: limit)
    }

    func fetchHomeFeedRange(start: Int, end: Int) async throws -> [Video] {
        let output = try await runYTDLPWithCookies(
            args: [
                "-j",
                "--flat-playlist",
                "--playlist-start", "\(start)",
                "--playlist-end", "\(end)",
                "https://www.youtube.com/"
            ]
        )
        return parseVideos(from: output)
    }

    func fetchSubscriptionsFeed(limit: Int = 30) async throws -> [Video] {
        return try await fetchSubscriptionsFeedRange(start: 1, end: limit)
    }

    func fetchSubscriptionsFeedRange(start: Int, end: Int) async throws -> [Video] {
        let output = try await runYTDLPWithCookies(
            args: [
                "-j",
                "--flat-playlist",
                "--playlist-start", "\(start)",
                "--playlist-end", "\(end)",
                "https://www.youtube.com/feed/subscriptions"
            ]
        )
        return parseVideos(from: output)
    }

    func fetchLiveFeed(limit: Int = 30) async throws -> [Video] {
        return try await fetchLiveFeedRange(start: 1, end: limit)
    }

    func fetchLiveFeedRange(start: Int, end: Int) async throws -> [Video] {
        do {
            let output = try await runYTDLPWithCookies(
                args: [
                    "-j",
                    "--flat-playlist",
                    "--playlist-start", "\(start)",
                    "--playlist-end", "\(end)",
                    "https://www.youtube.com/feed/live"
                ]
            )
            let videos = parseVideos(from: output, filter: Self.isLiveVideoJSON)
            if !videos.isEmpty {
                return videos
            }
        } catch {
            // Fall back to search if the Live tab endpoint is unavailable.
        }

        return try await fetchLiveSearchRange(start: start, end: end)
    }

    func fetchPlaylists(limit: Int = 30) async throws -> [Playlist] {
        return try await fetchPlaylistsRange(start: 1, end: limit)
    }

    func fetchPlaylistsRange(start: Int, end: Int) async throws -> [Playlist] {
        print("[YTDLPService] Fetching playlists from YouTube...")
        let output = try await runYTDLPWithCookies(
            args: [
                "-j",
                "--flat-playlist",
                "--playlist-start", "\(start)",
                "--playlist-end", "\(end)",
                "https://www.youtube.com/feed/playlists"
            ]
        )
        print("[YTDLPService] Raw output length: \(output.count) characters")
        let playlists = parsePlaylists(from: output)
        print("[YTDLPService] Parsed \(playlists.count) playlists")
        return playlists
    }

    func fetchPlaylistVideos(playlistId: String, limit: Int = 100) async throws -> [Video] {
        let url = "https://www.youtube.com/playlist?list=\(playlistId)"
        print("[YTDLPService] Fetching playlist videos from: \(url)")
        let output = try await runYTDLPWithCookies(
            args: ["-j", "--flat-playlist", "--playlist-end", "\(limit)", url]
        )
        print("[YTDLPService] Raw output length: \(output.count) characters")
        let videos = parseVideos(from: output)
        print("[YTDLPService] Parsed \(videos.count) videos from playlist")
        return videos
    }

    func fetchPlaylistVideosRange(playlistId: String, start: Int, end: Int) async throws -> [Video] {
        let url = "https://www.youtube.com/playlist?list=\(playlistId)"
        guard start <= end else { return [] }
        let output = try await runYTDLPWithCookies(
            args: ["-j", "--flat-playlist", "--playlist-items", "\(start)-\(end)", url]
        )
        return parseVideos(from: output)
    }

    func fetchPlaylistCount(playlistId: String) async throws -> Int? {
        let url = "https://www.youtube.com/playlist?list=\(playlistId)"
        let output = try await runYTDLPWithCookies(
            args: [
                "-J",
                "--flat-playlist",
                "--playlist-end", "1",
                url
            ]
        )

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTDLPError.parseError
        }

        guard json["playlist_count"] != nil else { return nil }
        return intValue(json["playlist_count"])
    }

    func search(query: String, limit: Int = 20) async throws -> [Video] {
        let searchQuery = "ytsearch\(limit):\(query)"
        let output = try await runYTDLP(
            args: ["-j", "--flat-playlist", searchQuery]
        )
        return parseVideos(from: output)
    }

    func getStreamURL(videoId: String, preferredQuality: String = "22/18") async throws -> URL {
        let url = "https://www.youtube.com/watch?v=\(videoId)"
        // Format 22 = 720p mp4 with audio, Format 18 = 360p mp4 with audio
        // These are pre-merged formats that work with AVPlayer
        let output = try await runYTDLPWithCookies(
            args: ["-f", preferredQuality, "-g", url]
        )

        let urls = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }

        guard let firstURL = urls.first, let streamURL = URL(string: firstURL) else {
            throw YTDLPError.noStreamURL
        }

        return streamURL
    }

    /// Fetches direct stream URLs for the requested format (separate video+audio when possible).
    /// Prefers H.264/H.265 MP4 video and AAC M4A audio for AVPlayer compatibility.
    func getStreams(videoId: String, format: VideoFormatOption?) async throws -> StreamURLs {
        let url = "https://www.youtube.com/watch?v=\(videoId)"
        let formatArg: String
        if let format, let formatId = format.formatId {
            if format.isMuxed {
                formatArg = formatId
            } else {
                formatArg = "\(formatId)+bestaudio[ext=m4a]/best"
            }
        } else {
            let maxHeight = SettingsService.shared.preferredQuality.maxHeight ?? 2160
            let heightFilter = "[height<=\(maxHeight)]"
            formatArg = "bestvideo[ext=mp4][vcodec^=avc1]\(heightFilter)+bestaudio[ext=m4a]/bestvideo[ext=mp4][vcodec^=hvc1]\(heightFilter)+bestaudio[ext=m4a]/bestvideo[ext=mp4][vcodec^=hev1]\(heightFilter)+bestaudio[ext=m4a]/best[ext=mp4]\(heightFilter)/best"
        }
        let output = try await runYTDLPWithCookies(
            args: ["-f", formatArg, "-g", url]
        )

        let urls = output
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if urls.count >= 2,
           let videoURL = URL(string: urls[0]),
           let audioURL = URL(string: urls[1]) {
            return StreamURLs(videoURL: videoURL, audioURL: audioURL, muxedURL: nil)
        }

        if let first = urls.first, let muxedURL = URL(string: first) {
            return StreamURLs(videoURL: nil, audioURL: nil, muxedURL: muxedURL)
        }

        throw YTDLPError.noStreamURL
    }

    func getMaxQualityStreams(videoId: String) async throws -> StreamURLs {
        return try await getStreams(videoId: videoId, format: nil)
    }

    /// Combined fetch that returns formats, channel, AND stream URLs from a single -J call
    /// This is much faster than making separate -J and -g calls
    func getVideoInfoCombined(videoId: String, requestedFormat: VideoFormatOption?) async throws -> (formats: [VideoFormatOption], channel: String?, streams: StreamURLs) {
        let url = "https://www.youtube.com/watch?v=\(videoId)"
        logger.info("getVideoInfoCombined: Fetching for video \(videoId)")

        let output = try await runYTDLPWithCookies(
            args: ["-J", "--no-playlist", url]
        )
        logger.info("getVideoInfoCombined: Got output, length: \(output.count)")

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formats = json["formats"] as? [[String: Any]] else {
            logger.error("getVideoInfoCombined: Failed to parse JSON or no formats array")
            throw YTDLPError.parseError
        }

        let channel = parseChannelName(from: json)
        let availableFormats = parseFormatsFromJSON(formats)
        let streams = try extractStreamURLs(from: formats, requestedFormat: requestedFormat)

        logger.info("getVideoInfoCombined: Parsed \(availableFormats.count) formats, channel: \(channel)")
        return (availableFormats, channel == "Unknown" ? nil : channel, streams)
    }

    /// Extract stream URLs from the formats JSON array
    private func extractStreamURLs(from formats: [[String: Any]], requestedFormat: VideoFormatOption?) throws -> StreamURLs {
        let preferredMaxHeight = SettingsService.shared.preferredQuality.maxHeight ?? 2160
        let heightFilter = min(preferredMaxHeight, 2160)
        let disableDubbed = SettingsService.shared.disableDubbedAudio
        let preferredLanguage = preferredAudioLanguage()

        // If a specific format is requested, find it
        if let format = requestedFormat, let formatId = format.formatId {
            if format.isMuxed {
                // Find the muxed format
                if let formatData = formats.first(where: { ($0["format_id"] as? String) == formatId }),
                   let urlString = formatData["url"] as? String,
                   let muxedURL = URL(string: urlString) {
                    return StreamURLs(videoURL: nil, audioURL: nil, muxedURL: muxedURL)
                }
            } else {
                // Find video format and best audio
                if let videoFormat = formats.first(where: { ($0["format_id"] as? String) == formatId }),
                   let videoURLString = videoFormat["url"] as? String,
                   let videoURL = URL(string: videoURLString),
                   let audioURL = findBestAudioURL(
                        from: formats,
                        disableDubbed: disableDubbed,
                        preferredLanguage: preferredLanguage
                   ) {
                    let fallbackMuxedURL = findBestMuxedURL(from: formats, maxHeight: heightFilter)
                    return StreamURLs(videoURL: videoURL, audioURL: audioURL, muxedURL: fallbackMuxedURL)
                }
            }
        }

        func resolveStreams(maxHeight: Int) -> StreamURLs? {
            let fallbackMuxedURL = findBestMuxedURL(from: formats, maxHeight: maxHeight)
            if let videoURL = findBestVideoURL(from: formats, maxHeight: maxHeight),
               let audioURL = findBestAudioURL(
                    from: formats,
                    disableDubbed: disableDubbed,
                    preferredLanguage: preferredLanguage
               ) {
                return StreamURLs(videoURL: videoURL, audioURL: audioURL, muxedURL: fallbackMuxedURL)
            }

            if let muxedURL = fallbackMuxedURL {
                return StreamURLs(videoURL: nil, audioURL: nil, muxedURL: muxedURL)
            }
            return nil
        }

        // Auto mode: try preferred max height first, then fall back to best available.
        if let streams = resolveStreams(maxHeight: heightFilter) {
            return streams
        }
        if heightFilter != 2160, let streams = resolveStreams(maxHeight: 2160) {
            return streams
        }

        throw YTDLPError.noStreamURL
    }

    private func findBestVideoURL(from formats: [[String: Any]], maxHeight: Int) -> URL? {
        let allowAV1 = !hasPreferredVideoCodec(formats)
        let videoFormats = formats.filter { format in
            let vcodec = format["vcodec"] as? String ?? "none"
            let acodec = format["acodec"] as? String ?? "none"
            let ext = format["ext"] as? String ?? ""
            let height = extractHeight(from: format)

            return vcodec != "none" && acodec == "none" &&
                   ext == "mp4" && isSupportedVideoCodec(vcodec, allowAV1: allowAV1) &&
                   height > 0 && height <= maxHeight
        }

        let sorted = videoFormats.sorted { lhs, rhs in
            let lhsPref = videoCodecPreference(lhs["vcodec"] as? String)
            let rhsPref = videoCodecPreference(rhs["vcodec"] as? String)
            if lhsPref != rhsPref { return lhsPref > rhsPref }
            let lhsHeight = extractHeight(from: lhs)
            let rhsHeight = extractHeight(from: rhs)
            if lhsHeight != rhsHeight { return lhsHeight > rhsHeight }
            let lhsTbr = lhs["tbr"] as? Double ?? 0
            let rhsTbr = rhs["tbr"] as? Double ?? 0
            return lhsTbr > rhsTbr
        }

        if let best = sorted.first,
           let urlString = best["url"] as? String {
            return URL(string: urlString)
        }
        return nil
    }

    private func findBestAudioURL(
        from formats: [[String: Any]],
        disableDubbed: Bool = false,
        preferredLanguage: String = ""
    ) -> URL? {
        var audioFormats = formats.filter { format in
            let vcodec = format["vcodec"] as? String ?? "none"
            let acodec = format["acodec"] as? String ?? "none"
            let ext = format["ext"] as? String ?? ""

            return vcodec == "none" && acodec != "none" && ext == "m4a"
        }

        guard !audioFormats.isEmpty else { return nil }

        let normalizedPreferred = normalizeLanguage(preferredLanguage)

        if disableDubbed {
            let withoutDub = audioFormats.filter { !isLikelyDubbedAudio($0) }
            if !withoutDub.isEmpty {
                audioFormats = withoutDub
            }
        }

        if !normalizedPreferred.isEmpty {
            let matches = audioFormats.filter { format in
                normalizeLanguage(format["language"] as? String).hasPrefix(normalizedPreferred)
            }
            if !matches.isEmpty {
                audioFormats = matches
            }
        } else if disableDubbed {
            let defaults = audioFormats.filter { isPreferredOriginalAudio($0) }
            if !defaults.isEmpty {
                audioFormats = defaults
            }
        }

        let sorted = audioFormats.sorted { lhs, rhs in
            let lhsScore = audioPreferenceScore(
                lhs,
                preferredLanguage: normalizedPreferred,
                disableDubbed: disableDubbed
            )
            let rhsScore = audioPreferenceScore(
                rhs,
                preferredLanguage: normalizedPreferred,
                disableDubbed: disableDubbed
            )
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            let lhsTbr = lhs["tbr"] as? Double ?? 0
            let rhsTbr = rhs["tbr"] as? Double ?? 0
            return lhsTbr > rhsTbr
        }

        if let best = sorted.first,
           let urlString = best["url"] as? String {
            return URL(string: urlString)
        }
        return nil
    }

    private func findBestMuxedURL(from formats: [[String: Any]], maxHeight: Int) -> URL? {
        let allowAV1 = !hasPreferredVideoCodec(formats)
        let muxedFormats = formats.filter { format in
            let vcodec = format["vcodec"] as? String ?? "none"
            let acodec = format["acodec"] as? String ?? "none"
            let ext = format["ext"] as? String ?? ""
            let height = extractHeight(from: format)

            return vcodec != "none" && acodec != "none" &&
                   ext == "mp4" && isSupportedVideoCodec(vcodec, allowAV1: allowAV1) &&
                   height > 0 && height <= maxHeight
        }

        let sorted = muxedFormats.sorted { lhs, rhs in
            let lhsPref = videoCodecPreference(lhs["vcodec"] as? String)
            let rhsPref = videoCodecPreference(rhs["vcodec"] as? String)
            if lhsPref != rhsPref { return lhsPref > rhsPref }
            let lhsHeight = extractHeight(from: lhs)
            let rhsHeight = extractHeight(from: rhs)
            if lhsHeight != rhsHeight { return lhsHeight > rhsHeight }
            let lhsTbr = lhs["tbr"] as? Double ?? 0
            let rhsTbr = rhs["tbr"] as? Double ?? 0
            return lhsTbr > rhsTbr
        }

        if let best = sorted.first,
           let urlString = best["url"] as? String {
            return URL(string: urlString)
        }
        return nil
    }

    private func audioPreferenceScore(
        _ format: [String: Any],
        preferredLanguage: String,
        disableDubbed: Bool
    ) -> Int {
        var score = 0
        let language = normalizeLanguage(format["language"] as? String)
        let languagePreference = intValue(format["language_preference"])
        let formatNote = (format["format_note"] as? String)?.lowercased() ?? ""
        let isDefault = boolValue(format["audio_is_default"]) || boolValue(format["is_default"])

        if !preferredLanguage.isEmpty {
            score += language.hasPrefix(preferredLanguage) ? 1000 : -200
        }

        if isDefault {
            score += 300
        }

        if languagePreference != 0 {
            score += languagePreference * 10
        }

        if formatNote.contains("original") {
            score += 150
        } else if formatNote.contains("default") {
            score += 100
        }

        if language.isEmpty || language == "und" {
            score += 50
        }

        if disableDubbed && isLikelyDubbedAudio(format) {
            score -= 500
        }

        return score
    }

    private func preferredAudioLanguage() -> String {
        let preferred = SettingsService.shared.preferredAudioLanguage
        return preferred.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isPreferredOriginalAudio(_ format: [String: Any]) -> Bool {
        let language = normalizeLanguage(format["language"] as? String)
        let languagePreference = intValue(format["language_preference"])
        let formatNote = (format["format_note"] as? String)?.lowercased() ?? ""
        let isDefault = boolValue(format["audio_is_default"]) || boolValue(format["is_default"])

        if isDefault { return true }
        if languagePreference > 0 { return true }
        if formatNote.contains("original") || formatNote.contains("default") { return true }
        if language.isEmpty || language == "und" { return true }
        return false
    }

    private func isLikelyDubbedAudio(_ format: [String: Any]) -> Bool {
        let language = (format["language"] as? String)?.lowercased() ?? ""
        let formatNote = (format["format_note"] as? String)?.lowercased() ?? ""
        let formatId = (format["format_id"] as? String)?.lowercased() ?? ""

        return language.contains("-dub") ||
            language.contains("dub") ||
            formatNote.contains("dub") ||
            formatId.contains("-dub")
    }

    private func normalizeLanguage(_ language: String?) -> String {
        let trimmed = (language ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        let normalized = trimmed.replacingOccurrences(of: "_", with: "-")
        return normalized.split(separator: "-").first.map(String.init) ?? normalized
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let boolValue = value as? Bool { return boolValue }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    private func intValue(_ value: Any?) -> Int {
        if let intValue = value as? Int { return intValue }
        if let number = value as? NSNumber { return number.intValue }
        if let doubleValue = value as? Double { return Int(doubleValue) }
        return 0
    }

    /// Parse format options from JSON array
    private func parseFormatsFromJSON(_ formats: [[String: Any]]) -> [VideoFormatOption] {
        var bestByKey: [String: (VideoFormatOption, Double)] = [:]
        let allowAV1 = !hasPreferredVideoCodec(formats)

        for format in formats {
            let height = extractHeight(from: format)
            if height <= 0 { continue }

            let formatId = format["format_id"] as? String ?? ""
            if formatId.isEmpty { continue }

            let vcodec = format["vcodec"] as? String ?? ""
            let acodec = format["acodec"] as? String ?? ""
            let ext = format["ext"] as? String ?? ""
            if vcodec == "none" || ext != "mp4" || !isSupportedVideoCodec(vcodec, allowAV1: allowAV1) { continue }

            let fps = format["fps"] as? Double
            let codecFamily = codecFamilyName(for: vcodec)
            let label = formatLabel(height: height, fps: fps, codecFamily: codecFamily)
            let option = VideoFormatOption(
                id: formatId,
                label: label,
                formatId: formatId,
                height: height,
                fps: fps,
                codecFamily: codecFamily,
                isMuxed: acodec != "none"
            )

            let key = "\(height)|\(Int((fps ?? 0).rounded()))|\(codecFamily ?? "")"
            let tbr = format["tbr"] as? Double ?? 0
            if let existing = bestByKey[key], existing.1 >= tbr { continue }
            bestByKey[key] = (option, tbr)
        }

        var available: [VideoFormatOption] = [.auto]
        let sorted = bestByKey.values
            .map { $0.0 }
            .sorted { lhs, rhs in
                let lhsHeight = lhs.height ?? 0
                let rhsHeight = rhs.height ?? 0
                if lhsHeight != rhsHeight { return lhsHeight > rhsHeight }
                let lhsFps = lhs.fps ?? 0
                let rhsFps = rhs.fps ?? 0
                if lhsFps != rhsFps { return lhsFps > rhsFps }
                let lhsCodec = lhs.codecFamily ?? ""
                let rhsCodec = rhs.codecFamily ?? ""
                return lhsCodec > rhsCodec
            }
        available.append(contentsOf: sorted)
        return available
    }

    /// Returns (formats, channelName) - channel name is extracted from the same -J response
    func getAvailableFormats(videoId: String) async throws -> (formats: [VideoFormatOption], channel: String?) {
        let url = "https://www.youtube.com/watch?v=\(videoId)"
        logger.info("getAvailableFormats: Fetching for video \(videoId)")

        let output: String
        do {
            output = try await runYTDLPWithCookies(
                args: ["-J", "--no-playlist", url]
            )
            logger.info("getAvailableFormats: Got output, length: \(output.count)")
        } catch {
            logger.error("getAvailableFormats: runYTDLP failed: \(error.localizedDescription)")
            throw error
        }

        guard let data = output.data(using: .utf8) else {
            logger.error("getAvailableFormats: Failed to convert output to data")
            throw YTDLPError.parseError
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("getAvailableFormats: Failed to parse JSON")
            logger.debug("First 500 chars: \(String(output.prefix(500)))")
            throw YTDLPError.parseError
        }

        // Extract channel name from the response
        let channel = parseChannelName(from: json)
        logger.info("getAvailableFormats: Extracted channel: \(channel)")

        guard let formats = json["formats"] as? [[String: Any]] else {
            logger.error("getAvailableFormats: No 'formats' array in JSON")
            throw YTDLPError.parseError
        }

        logger.info("getAvailableFormats: Total formats from yt-dlp: \(formats.count)")
        let allowAV1 = !hasPreferredVideoCodec(formats)

        var bestByKey: [String: (VideoFormatOption, Double)] = [:]
        var skippedNoHeight = 0
        var skippedNoFormatId = 0
        var skippedCodecOrExt = 0

        for format in formats {
            let height = extractHeight(from: format)
            if height <= 0 {
                skippedNoHeight += 1
                continue
            }

            let formatId = format["format_id"] as? String ?? ""
            if formatId.isEmpty {
                skippedNoFormatId += 1
                continue
            }

            let vcodec = format["vcodec"] as? String ?? ""
            let acodec = format["acodec"] as? String ?? ""
            let ext = format["ext"] as? String ?? ""
            if vcodec == "none" || ext != "mp4" || !isSupportedVideoCodec(vcodec, allowAV1: allowAV1) {
                skippedCodecOrExt += 1
                continue
            }

            let fps = format["fps"] as? Double
            let codecFamily = codecFamilyName(for: vcodec)
            let label = formatLabel(height: height, fps: fps, codecFamily: codecFamily)
            let option = VideoFormatOption(
                id: formatId,
                label: label,
                formatId: formatId,
                height: height,
                fps: fps,
                codecFamily: codecFamily,
                isMuxed: acodec != "none"
            )

            let key = "\(height)|\(Int((fps ?? 0).rounded()))|\(codecFamily ?? "")"
            let tbr = format["tbr"] as? Double ?? 0
            if let existing = bestByKey[key], existing.1 >= tbr {
                continue
            }
            bestByKey[key] = (option, tbr)
        }

        logger.info("getAvailableFormats: Skipped - noHeight: \(skippedNoHeight), noFormatId: \(skippedNoFormatId), codecOrExt: \(skippedCodecOrExt)")
        logger.info("getAvailableFormats: Kept \(bestByKey.count) unique format options")

        var available: [VideoFormatOption] = [.auto]
        let sorted = bestByKey.values
            .map { $0.0 }
            .sorted { lhs, rhs in
                let lhsHeight = lhs.height ?? 0
                let rhsHeight = rhs.height ?? 0
                if lhsHeight != rhsHeight { return lhsHeight > rhsHeight }
                let lhsFps = lhs.fps ?? 0
                let rhsFps = rhs.fps ?? 0
                if lhsFps != rhsFps { return lhsFps > rhsFps }
                let lhsCodec = lhs.codecFamily ?? ""
                let rhsCodec = rhs.codecFamily ?? ""
                return lhsCodec > rhsCodec
            }
        available.append(contentsOf: sorted)

        for opt in available {
            logger.info("getAvailableFormats: Format option: \(opt.label) (id: \(opt.id))")
        }

        return (available, channel == "Unknown" ? nil : channel)
    }

    private func extractHeight(from format: [String: Any]) -> Int {
        if let heightNumber = format["height"] as? NSNumber {
            return heightNumber.intValue
        }
        if let heightDouble = format["height"] as? Double {
            return Int(heightDouble)
        }
        if let note = format["format_note"] as? String {
            let digits = note.prefix { $0.isNumber }
            if let height = Int(digits) {
                return height
            }
        }
        return 0
    }

    private func isSupportedVideoCodec(_ vcodec: String, allowAV1: Bool = true) -> Bool {
        let codec = vcodec.lowercased()
        if isPreferredVideoCodec(codec) { return true }
        return allowAV1 && codec.contains("av01")
    }

    private func isPreferredVideoCodec(_ vcodec: String) -> Bool {
        let codec = vcodec.lowercased()
        return codec.contains("avc1") || codec.contains("hvc1") || codec.contains("hev1")
    }

    private func hasPreferredVideoCodec(_ formats: [[String: Any]]) -> Bool {
        formats.contains { format in
            let vcodec = format["vcodec"] as? String ?? "none"
            let ext = format["ext"] as? String ?? ""
            return vcodec != "none" && ext == "mp4" && isPreferredVideoCodec(vcodec)
        }
    }

    private func codecFamilyName(for vcodec: String) -> String? {
        let codec = vcodec.lowercased()
        if codec.contains("avc1") {
            return "H.264"
        }
        if codec.contains("hvc1") || codec.contains("hev1") {
            return "H.265"
        }
        if codec.contains("av01") {
            return "AV1"
        }
        return nil
    }

    private func videoCodecPreference(_ vcodec: String?) -> Int {
        let codec = (vcodec ?? "").lowercased()
        if codec.contains("avc1") {
            return 3
        }
        if codec.contains("hvc1") || codec.contains("hev1") {
            return 2
        }
        if codec.contains("av01") {
            return 1
        }
        return 0
    }

    private func formatLabel(height: Int, fps: Double?, codecFamily: String?) -> String {
        let fpsLabel = fps != nil && (fps ?? 0) > 0 ? "\(Int((fps ?? 0).rounded()))" : ""
        let resolution = fpsLabel.isEmpty ? "\(height)p" : "\(height)p\(fpsLabel)"
        if let codecFamily {
            return "\(resolution) • \(codecFamily)"
        }
        return resolution
    }

    /// Downloads video with best quality (video+audio merged) to temp file
    /// Returns the local file URL when ready to play
    /// Note: Uses H.264 (avc1) codec for AVPlayer compatibility - VP9/WebM won't play
    func downloadVideo(
        videoId: String,
        quality: String = "bestvideo[height<=1080][vcodec^=avc1]+bestaudio[acodec^=mp4a]/bestvideo[height<=1080][vcodec^=avc]+bestaudio/best[ext=mp4]/best",
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> URL {
        let url = "https://www.youtube.com/watch?v=\(videoId)"
        let tempDir = FileManager.default.temporaryDirectory
        let outputPath = tempDir.appendingPathComponent("\(videoId).mp4")

        // Delete existing file if present
        try? FileManager.default.removeItem(at: outputPath)

        // Download with progress
        try await runYTDLPWithCookiesProgress(
            args: [
                "-f", quality,
                "--merge-output-format", "mp4",
                "-o", outputPath.path,
                "--newline",  // Progress on new lines
                "--progress-template", "%(progress._percent_str)s %(progress._speed_str)s",
                url
            ],
            progressHandler: progressHandler
        )

        guard FileManager.default.fileExists(atPath: outputPath.path) else {
            throw YTDLPError.downloadFailed
        }

        return outputPath
    }

    /// Pre-download a video in background (for playlist pre-buffering)
    func preloadVideo(videoId: String) async throws -> URL {
        return try await downloadVideo(videoId: videoId, progressHandler: { _, _ in })
    }

    private func runYTDLPWithProgress(
        args: [String],
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        let executablePath = self.ytdlpPath  // Capture before leaving actor context
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = args

                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                env["HOME"] = NSHomeDirectory()
                process.environment = env

                let pipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errorPipe

                // Read output progressively
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !line.isEmpty {
                        // Parse progress: "50.0% 5.00MiB/s"
                        let parts = line.split(separator: " ")
                        if let percentStr = parts.first,
                           let percent = Double(percentStr.replacingOccurrences(of: "%", with: "")) {
                            let speed = parts.count > 1 ? String(parts[1]) : ""
                            DispatchQueue.main.async {
                                progressHandler(percent / 100.0, speed)
                            }
                        }
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    pipe.fileHandleForReading.readabilityHandler = nil

                    if process.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorOutput = String(data: errorData, encoding: .utf8) ?? "Download failed"
                        continuation.resume(throwing: YTDLPError.processError(errorOutput))
                    } else {
                        continuation.resume(returning: ())
                    }
                } catch {
                    continuation.resume(throwing: YTDLPError.processError(error.localizedDescription))
                }
            }
        }
    }

    private func runYTDLPWithCookiesProgress(
        args: [String],
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        var lastError: Error?
        for browser in cookieBrowsers() {
            do {
                return try await runYTDLPWithProgress(
                    args: ["--cookies-from-browser", browser.ytDlpValue] + args,
                    progressHandler: progressHandler
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? YTDLPError.processError("Unable to read browser cookies.")
    }

    func getVideoInfo(videoId: String) async throws -> Video {
        let url = "https://www.youtube.com/watch?v=\(videoId)"
        let output = try await runYTDLPWithCookies(
            args: ["-j", "--no-playlist", url]
        )

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTDLPError.parseError
        }

        return parseVideoFromJSON(json)
    }

    // MARK: - Private Methods

    private func runYTDLP(args: [String]) async throws -> String {
        let executablePath = self.ytdlpPath  // Capture before leaving actor context
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = args

                // Ensure yt-dlp has access to homebrew paths
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                env["HOME"] = NSHomeDirectory()
                process.environment = env

                let pipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errorPipe

                // Read output asynchronously to prevent pipe buffer deadlock
                // (macOS pipes have ~64KB buffer; larger output blocks the process)
                let outputBuffer = OutputBuffer()
                let errorBuffer = OutputBuffer()

                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    outputBuffer.append(data)
                }

                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    errorBuffer.append(data)
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    // Stop reading handlers
                    pipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil

                    // Read any remaining data
                    let remainingOutput = pipe.fileHandleForReading.readDataToEndOfFile()
                    let remainingError = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    outputBuffer.append(remainingOutput)
                    errorBuffer.append(remainingError)

                    let output = String(data: outputBuffer.value(), encoding: .utf8) ?? ""

                    // If we got valid output, use it even if there were warnings on stderr
                    if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continuation.resume(returning: output)
                    } else if process.terminationStatus != 0 {
                        let errorOutput = String(data: errorBuffer.value(), encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: YTDLPError.processError(errorOutput))
                    } else {
                        continuation.resume(returning: output)
                    }
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: YTDLPError.processError(error.localizedDescription))
                }
            }
        }
    }

    private func cookieBrowsers() -> [CookiesBrowser] {
        if let browserOverride {
            if browserOverride == .auto {
                return CookiesBrowser.autoFallbackOrder
            }
            return [browserOverride]
        }

        let selection = SettingsService.shared.cookiesBrowser
        if selection == .auto {
            return CookiesBrowser.autoFallbackOrder
        }
        return [selection]
    }

    private func runYTDLPWithCookies(args: [String]) async throws -> String {
        var lastError: Error?
        for browser in cookieBrowsers() {
            do {
                return try await runYTDLP(
                    args: ["--cookies-from-browser", browser.ytDlpValue] + args
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? YTDLPError.processError("Unable to read browser cookies.")
    }

    private func parseVideos(from output: String) -> [Video] {
        return parseVideos(from: output, filter: nil)
    }

    private func parseVideos(
        from output: String,
        filter: (([String: Any]) -> Bool)?
    ) -> [Video] {
        let lines = output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty && $0.hasPrefix("{") }
        return lines.compactMap { line -> Video? in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            if let filter, !filter(json) {
                return nil
            }
            return parseVideoFromJSON(json)
        }
    }

    private func parseVideoFromJSON(_ json: [String: Any]) -> Video {
        let id = json["id"] as? String ?? json["url"] as? String ?? UUID().uuidString

        // Handle thumbnail - can be string or array of dicts
        var thumbnailURL: URL? = nil
        if let thumbnailString = json["thumbnail"] as? String {
            thumbnailURL = URL(string: thumbnailString)
        } else if let thumbnails = json["thumbnails"] as? [[String: Any]],
                  let lastThumb = thumbnails.last,
                  let urlString = lastThumb["url"] as? String {
            thumbnailURL = URL(string: urlString)
        }

        // Parse duration
        var duration: TimeInterval? = nil
        if let durationValue = json["duration"] as? Double {
            duration = durationValue
        } else if let durationString = json["duration_string"] as? String {
            duration = parseDurationString(durationString)
        }

        // Parse upload date
        var publishedAt: Date? = nil
        if let uploadDate = json["upload_date"] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            publishedAt = formatter.date(from: uploadDate)
        }

        let viewCountValue = json["view_count"]
        let viewCount = viewCountValue == nil ? nil : intValue(viewCountValue)

        return Video(
            id: id,
            title: json["title"] as? String ?? "Unknown",
            channel: parseChannelName(from: json),
            channelId: json["channel_id"] as? String ?? json["uploader_id"] as? String,
            thumbnailURL: thumbnailURL,
            duration: duration,
            viewCount: viewCount,
            publishedAt: publishedAt
        )
    }

    private func parsePlaylists(from output: String) -> [Playlist] {
        let lines = output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty && $0.hasPrefix("{") }
        return lines.compactMap { line -> Playlist? in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            let id = json["id"] as? String ??
                json["playlist_id"] as? String ??
                extractPlaylistId(from: json["url"] as? String) ??
                extractPlaylistId(from: json["webpage_url"] as? String) ??
                UUID().uuidString

            var thumbnailURL: URL? = nil
            if let thumbnailString = json["thumbnail"] as? String {
                thumbnailURL = URL(string: thumbnailString)
            } else if let thumbnails = json["thumbnails"] as? [[String: Any]],
                      let lastThumb = thumbnails.last,
                      let urlString = lastThumb["url"] as? String {
                thumbnailURL = URL(string: urlString)
            }

            let countValue = json["playlist_count"]
            let rawCount = countValue == nil ? nil : intValue(countValue)
            let videoCount: Int?
            if let rawCount, rawCount > 0 {
                videoCount = rawCount
            } else {
                videoCount = nil
            }

            return Playlist(
                id: id,
                title: json["title"] as? String ?? "Unknown Playlist",
                thumbnailURL: thumbnailURL,
                videoCount: videoCount,
                channel: parseChannelName(from: json)
            )
        }
    }

    private static func isLiveVideoJSON(_ json: [String: Any]) -> Bool {
        if let isLive = json["is_live"] as? Bool {
            return isLive
        }
        if let liveStatus = json["live_status"] as? String {
            return liveStatus == "is_live"
        }
        return false
    }

    private func parseDurationString(_ string: String) -> TimeInterval {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 1: return TimeInterval(parts[0])
        case 2: return TimeInterval(parts[0] * 60 + parts[1])
        case 3: return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
        default: return 0
        }
    }

    private func extractPlaylistId(from urlString: String?) -> String? {
        let trimmed = (urlString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let components = URLComponents(string: trimmed),
           let list = components.queryItems?.first(where: { $0.name == "list" })?.value,
           !list.isEmpty {
            return list
        }

        let knownPrefixes = ["PL", "LL", "UU", "OLAK", "RD", "FL", "WL"]
        if knownPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return trimmed
        }

        return nil
    }

    private func fetchLiveSearchRange(start: Int, end: Int) async throws -> [Video] {
        let targetEnd = max(end, 1)
        let maxLimit = 200
        var limit = max(targetEnd * 3, 30)
        var attempt = 0
        var videos: [Video] = []

        while attempt < 3 {
            let output = try await runYTDLP(
                args: [
                    "-j",
                    "--flat-playlist",
                    "ytsearch\(limit):live"
                ]
            )
            videos = parseVideos(from: output, filter: Self.isLiveVideoJSON)
            if videos.count >= targetEnd || limit >= maxLimit {
                break
            }
            attempt += 1
            limit = min(maxLimit, max(limit * 2, targetEnd * 4))
        }

        if start <= 1 {
            return Array(videos.prefix(targetEnd))
        }
        let startIndex = max(0, start - 1)
        guard startIndex < videos.count else { return [] }
        let endIndex = min(videos.count, end)
        return Array(videos[startIndex..<endIndex])
    }

    private func parseChannelName(from json: [String: Any]) -> String {
        let directCandidates: [String?] = [
            json["channel"] as? String,
            json["uploader"] as? String,
            json["channel_name"] as? String,
            json["uploader_name"] as? String
        ]

        for candidate in directCandidates {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty,
               value != "Unknown" {
                return value
            }
        }

        if let urlString = json["channel_url"] as? String ?? json["uploader_url"] as? String,
           let handle = extractHandle(from: urlString) {
            return handle
        }

        if let uploaderId = json["uploader_id"] as? String, !uploaderId.isEmpty {
            return uploaderId
        }

        if let channelId = json["channel_id"] as? String, !channelId.isEmpty {
            return channelId
        }

        return "Unknown"
    }

    private func extractHandle(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if let handle = parts.first(where: { $0.hasPrefix("@") }) {
            return handle
        }
        if let last = parts.last, !last.isEmpty {
            return last
        }
        return nil
    }
}

// MARK: - Errors

enum YTDLPError: LocalizedError {
    case processError(String)
    case parseError
    case noStreamURL
    case notInstalled
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .processError(let message):
            return "yt-dlp error: \(message)"
        case .parseError:
            return "Failed to parse yt-dlp output"
        case .noStreamURL:
            return "No stream URL found"
        case .notInstalled:
            return "yt-dlp is not installed. Run: brew install yt-dlp"
        case .downloadFailed:
            return "Download failed - file not found"
        }
    }
}
