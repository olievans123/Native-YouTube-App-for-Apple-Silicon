import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @StateObject private var viewModel = PlaylistDetailViewModel()
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(playlist.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    if let count = viewModel.totalVideoCount ?? playlist.videoCount {
                        Text("\(count) videos")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Loading count...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            Group {
                if viewModel.isLoading {
                    LoadingView(message: "Loading playlist...")
                } else if let error = viewModel.error, viewModel.videos.isEmpty {
                    ErrorView(message: error) {
                        Task {
                            await viewModel.loadVideos(
                                playlistId: playlist.id,
                                expectedCount: playlist.videoCount
                            )
                        }
                    }
                } else if viewModel.videos.isEmpty && viewModel.hasAttemptedLoad {
                    EmptyStateView(
                        icon: "music.note.list",
                        title: "Empty playlist",
                        message: "This playlist has no videos"
                    )
                } else if viewModel.videos.isEmpty {
                    // Still loading initial state
                    LoadingView(message: "Loading playlist...")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(viewModel.videos.enumerated()), id: \.offset) { index, video in
                                VideoRow(video: video) {
                                    dismiss()
                                    playerViewModel.requestTheater()
                                    Task {
                                        await playerViewModel.playVideoFromPlaylist(
                                            video,
                                            playlist: viewModel.videos,
                                            startIndex: index
                                        )
                                    }
                                }
                                .padding(.horizontal)
                                .onAppear {
                                    let triggerIndex = max(0, viewModel.videos.count - 3)
                                    if viewModel.hasMore,
                                       index >= triggerIndex,
                                       !viewModel.isLoadingMore,
                                       !playerViewModel.isPlaying,
                                       !playerViewModel.isLoading {
                                        Task { await viewModel.loadMore() }
                                    }
                                }
                            }

                            if viewModel.hasMore {
                                if viewModel.isLoadingMore {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                        Spacer()
                                    }
                                    .padding(.vertical)
                                } else {
                                    Button(action: {
                                        Task { await viewModel.loadMore() }
                                    }) {
                                        HStack {
                                            Spacer()
                                            Text("Load More")
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.vertical)
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .task(id: playlist.id) {
            // Always load when playlist changes (task(id:) re-runs when id changes)
            print("[PlaylistDetailView] Task triggered for playlist: \(playlist.id)")
            await viewModel.loadVideos(playlistId: playlist.id, expectedCount: playlist.videoCount)
        }
    }
}
