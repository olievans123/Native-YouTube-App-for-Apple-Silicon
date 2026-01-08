import SwiftUI

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var isLoading = false

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                content(Image(nsImage: image))
            } else {
                placeholder()
                    .task(id: url) {
                        await loadImage()
                    }
            }
        }
    }

    private func loadImage() async {
        guard let url, !isLoading else { return }
        isLoading = true

        if let cached = await ThumbnailCacheService.shared.getImage(for: url) {
            await MainActor.run {
                self.image = cached
            }
        }

        isLoading = false
    }
}

// Convenience initializer with phase-based content
struct CachedAsyncImagePhase<Content: View>: View {
    let url: URL?
    let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(
        url: URL?,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                await loadImage()
            }
    }

    private func loadImage() async {
        guard let url else {
            phase = .empty
            return
        }

        phase = .empty

        if let cached = await ThumbnailCacheService.shared.getImage(for: url) {
            phase = .success(Image(nsImage: cached))
        } else {
            phase = .failure(URLError(.badServerResponse))
        }
    }
}
