import Foundation

struct Playlist: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let thumbnailURL: URL?
    let videoCount: Int?
    let channel: String?
}
