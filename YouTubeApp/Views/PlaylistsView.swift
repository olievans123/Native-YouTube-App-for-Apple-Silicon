import SwiftUI

struct PlaylistsView: View {
    @ObservedObject var viewModel: PlaylistsViewModel
    @State private var selectedPlaylist: Playlist?
    @EnvironmentObject var playerViewModel: PlayerViewModel
    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 20)]

    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingView(message: "Loading playlists...")
            } else if let error = viewModel.error, viewModel.playlists.isEmpty {
                ErrorView(message: error) {
                    Task { await viewModel.loadPlaylists() }
                }
            } else if viewModel.playlists.isEmpty && viewModel.hasAttemptedLoad {
                EmptyStateView(
                    icon: "list.bullet.rectangle",
                    title: "No playlists",
                    message: "Create playlists on YouTube to see them here"
                )
            } else if viewModel.playlists.isEmpty {
                LoadingView(message: "Loading playlists...")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(viewModel.playlists.indices, id: \.self) { index in
                            let playlist = viewModel.playlists[index]
                            Button {
                                selectedPlaylist = playlist
                            } label: {
                                PlaylistCard(playlist: playlist)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                viewModel.loadPlaylistCountIfNeeded(for: playlist)
                                let triggerIndex = max(0, viewModel.playlists.count - 3)
                                if viewModel.hasMore,
                                   index >= triggerIndex,
                                   !viewModel.isLoadingMore,
                                   !playerViewModel.isPlaying,
                                   !playerViewModel.isLoading {
                                    Task { await viewModel.loadMore() }
                                }
                            }
                        }
                    }
                    .padding()

                    if viewModel.hasMore {
                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.bottom)
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
                            .padding(.bottom)
                        }
                    }
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { Task { await viewModel.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task {
            if !viewModel.hasAttemptedLoad {
                await viewModel.loadPlaylists()
            }
        }
        .sheet(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(playlist: playlist)
                .environmentObject(playerViewModel)
        }
    }
}

struct PlaylistCard: View {
    let playlist: Playlist

    private var countText: String {
        if let count = playlist.videoCount {
            return "\(count) videos"
        }
        return "Loading..."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(url: playlist.thumbnailURL) { image in
                    image.resizable().aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.2)
                        .aspectRatio(16/9, contentMode: .fill)
                        .overlay {
                            ProgressView()
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(countText)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.8))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let channel = playlist.channel, channel != "Unknown" {
                    Text(channel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
