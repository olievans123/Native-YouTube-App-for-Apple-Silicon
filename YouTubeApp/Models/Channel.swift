import Foundation

struct Channel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let thumbnailURL: URL?
}
