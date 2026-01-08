import SwiftUI
import AVKit

struct VideoPlayerView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @State private var isFullscreen = false
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black

            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showControls.toggle()
                        }
                        scheduleHideControls()
                    }
            }

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(.circular)
            }

            if showControls {
                controlsOverlay
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            scheduleHideControls()
        }
    }

    private var controlsOverlay: some View {
        VStack {
            HStack {
                if let video = viewModel.currentVideo {
                    VStack(alignment: .leading) {
                        Text(video.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(video.channel)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()

                Button(action: toggleFullscreen) {
                    Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.7), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Spacer()

            HStack(spacing: 32) {
                Button(action: { viewModel.seek(by: -10) }) {
                    Image(systemName: "gobackward.10")
                        .font(.title)
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.togglePlayback() }) {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.seek(by: 10) }) {
                    Image(systemName: "goforward.10")
                        .font(.title)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            HStack {
                Spacer()
                // Picture in Picture button
                Button(action: { /* PiP handled by AVPlayerView */ }) {
                    Image(systemName: "pip.enter")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .foregroundColor(.white)
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls = false
                    }
                }
            }
        }
    }

    private func toggleFullscreen() {
        isFullscreen.toggle()
        if let window = NSApplication.shared.windows.first {
            window.toggleFullScreen(nil)
        }
    }
}

