import Foundation

struct Video: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let channel: String
    let channelId: String?
    let thumbnailURL: URL?
    let duration: TimeInterval?
    let viewCount: Int?
    let publishedAt: Date?

    var durationString: String {
        guard let duration = duration else { return "" }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var relativeDate: String {
        guard let date = publishedAt else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var viewCountString: String {
        guard let count = viewCount else { return "" }
        if count >= 1_000_000 {
            return String(format: "%.1fM views", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK views", Double(count) / 1_000)
        } else {
            return "\(count) views"
        }
    }
}

struct VideoFormatOption: Identifiable, Hashable, Codable {
    let id: String
    let label: String
    let formatId: String?
    let height: Int?
    let fps: Double?
    let codecFamily: String?
    let isMuxed: Bool

    static let auto = VideoFormatOption(
        id: "auto",
        label: "Auto",
        formatId: nil,
        height: nil,
        fps: nil,
        codecFamily: nil,
        isMuxed: false
    )

    var shortLabel: String {
        guard let height, height > 0 else { return label }
        if let fps, fps > 0 {
            return "\(height)p\(Int(fps.rounded()))"
        }
        return "\(height)p"
    }
}
