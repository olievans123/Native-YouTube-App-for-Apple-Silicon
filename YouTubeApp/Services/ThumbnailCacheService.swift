import Foundation
import AppKit

actor ThumbnailCacheService {
    static let shared = ThumbnailCacheService()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let memoryCache = NSCache<NSString, NSImage>()
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("ThumbnailCache", isDirectory: true)

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Configure memory cache
        memoryCache.countLimit = 200

        // Clean old cache entries periodically
        Task {
            await cleanOldCacheEntries()
        }
    }

    func getImage(for url: URL) async -> NSImage? {
        let key = cacheKey(for: url)

        // Check memory cache first
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // Check disk cache
        let filePath = cacheDirectory.appendingPathComponent(key)
        if fileManager.fileExists(atPath: filePath.path),
           let image = NSImage(contentsOf: filePath) {
            // Store in memory cache
            memoryCache.setObject(image, forKey: key as NSString)
            return image
        }

        // Download and cache
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = NSImage(data: data) else { return nil }

            // Save to disk
            try? data.write(to: filePath)

            // Store in memory cache
            memoryCache.setObject(image, forKey: key as NSString)

            return image
        } catch {
            return nil
        }
    }

    private func cacheKey(for url: URL) -> String {
        // Create a safe filename from the URL
        let hash = url.absoluteString.data(using: .utf8)!
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return String(hash.prefix(64))
    }

    private func cleanOldCacheEntries() {
        let cutoffDate = Date().addingTimeInterval(-maxCacheAge)

        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for fileURL in contents {
            guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let modDate = attributes[.modificationDate] as? Date,
                  modDate < cutoffDate else { continue }

            try? fileManager.removeItem(at: fileURL)
        }
    }

    func clearCache() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
