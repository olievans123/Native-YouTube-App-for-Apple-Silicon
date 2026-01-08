import Foundation

actor FormatCacheService {
    static let shared = FormatCacheService()

    private let defaults = UserDefaults.standard
    private let cacheKey = "formatCache"
    private let maxAge: TimeInterval = 86400 // 24 hours
    private let maxCacheEntries = 100

    private struct CachedFormats: Codable {
        let videoId: String
        let formats: [VideoFormatOption]
        let timestamp: Date

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 86400
        }
    }

    func getCachedFormats(for videoId: String) -> [VideoFormatOption]? {
        let cache = loadCache()
        guard let entry = cache.first(where: { $0.videoId == videoId }),
              !entry.isExpired else {
            return nil
        }
        return entry.formats
    }

    func cacheFormats(_ formats: [VideoFormatOption], for videoId: String) {
        var cache = loadCache()

        // Remove existing entry for this video
        cache.removeAll { $0.videoId == videoId }

        // Remove expired entries
        cache.removeAll { $0.isExpired }

        // Add new entry
        cache.insert(CachedFormats(
            videoId: videoId,
            formats: formats,
            timestamp: Date()
        ), at: 0)

        // Trim to max entries
        if cache.count > maxCacheEntries {
            cache = Array(cache.prefix(maxCacheEntries))
        }

        saveCache(cache)
    }

    func clearCache() {
        defaults.removeObject(forKey: cacheKey)
    }

    private func loadCache() -> [CachedFormats] {
        guard let data = defaults.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode([CachedFormats].self, from: data) else {
            return []
        }
        return cache
    }

    private func saveCache(_ cache: [CachedFormats]) {
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: cacheKey)
        }
    }
}
