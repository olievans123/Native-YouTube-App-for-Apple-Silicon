import SwiftUI

struct SubscriptionsView: View {
    @ObservedObject var viewModel: SubscriptionsViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.videos.isEmpty {
                LoadingView(message: "Loading subscriptions...")
            } else if let error = viewModel.error, viewModel.videos.isEmpty {
                ErrorView(message: error) {
                    Task { await viewModel.loadVideos() }
                }
            } else if viewModel.videos.isEmpty {
                EmptyStateView(
                    icon: "play.square.stack",
                    title: "No subscriptions",
                    message: "Subscribe to channels to see their videos here"
                )
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        VideoGrid(
                            videos: viewModel.videos,
                            onVideoTap: { video in
                                playerViewModel.requestTheater()
                                Task { await playerViewModel.playVideo(video) }
                            },
                            onScrolledToEnd: {
                                if viewModel.hasMore,
                                   !viewModel.isLoadingMore,
                                   !playerViewModel.isPlaying,
                                   !playerViewModel.isLoading {
                                    Task { await viewModel.loadMore() }
                                }
                            }
                        )

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
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .navigationTitle("Subscriptions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { Task { await viewModel.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task {
            if viewModel.videos.isEmpty {
                await viewModel.loadVideos()
            }
        }
    }
}
