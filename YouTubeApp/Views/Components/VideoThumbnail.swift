import SwiftUI

struct VideoThumbnail: View {
    let video: Video
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImagePhase(url: video.thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                        case .failure:
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .aspectRatio(16/9, contentMode: .fill)
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundColor(.secondary)
                                }
                        case .empty:
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .aspectRatio(16/9, contentMode: .fill)
                                .overlay {
                                    ProgressView()
                                }
                        @unknown default:
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .aspectRatio(16/9, contentMode: .fill)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if !video.durationString.isEmpty {
                        Text(video.durationString)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.8))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)

                    if video.channel != "Unknown" {
                        Text(video.channel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        if !video.viewCountString.isEmpty {
                            Text(video.viewCountString)
                        }
                        if !video.viewCountString.isEmpty && !video.relativeDate.isEmpty {
                            Text("•")
                        }
                        if !video.relativeDate.isEmpty {
                            Text(video.relativeDate)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

struct VideoGrid: View {
    let videos: [Video]
    let onVideoTap: (Video) -> Void
    var onScrolledToEnd: (() -> Void)? = nil
    var prefetchThreshold: Int = 6

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 20)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 24) {
            ForEach(videos.indices, id: \.self) { index in
                let video = videos[index]
                VideoThumbnail(video: video) {
                    onVideoTap(video)
                }
                .onAppear {
                    guard let onScrolledToEnd else { return }
                    let triggerIndex = max(0, videos.count - prefetchThreshold)
                    if index >= triggerIndex {
                        onScrolledToEnd()
                    }
                }
            }
        }
        .padding()
    }
}

struct VideoRow: View {
    let video: Video
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImage(url: video.thumbnailURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                    .frame(width: 160, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    if !video.durationString.isEmpty {
                        Text(video.durationString)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.8))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(4)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundColor(.primary)

                    Text(video.channel)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        if !video.viewCountString.isEmpty {
                            Text(video.viewCountString)
                        }
                        if !video.viewCountString.isEmpty && !video.relativeDate.isEmpty {
                            Text("•")
                        }
                        if !video.relativeDate.isEmpty {
                            Text(video.relativeDate)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
