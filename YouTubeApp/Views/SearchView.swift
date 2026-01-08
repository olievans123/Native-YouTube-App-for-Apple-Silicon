import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @EnvironmentObject var playerViewModel: PlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search YouTube", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task { await viewModel.search() }
                    }

                if !viewModel.query.isEmpty {
                    Button(action: { viewModel.clear() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding()

            Divider()

            if viewModel.isLoading {
                LoadingView(message: "Searching...")
            } else if let error = viewModel.error, viewModel.videos.isEmpty {
                ErrorView(message: error) {
                    Task { await viewModel.search() }
                }
            } else if viewModel.hasSearched && viewModel.videos.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No results",
                    message: "Try a different search term"
                )
            } else if !viewModel.hasSearched {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "Search YouTube",
                    message: "Enter a search term to find videos"
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
            }
        }
        .navigationTitle("Search")
    }
}
