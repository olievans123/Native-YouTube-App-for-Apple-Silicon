import SwiftUI
import AVKit
import Combine

enum NavigationItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case subscriptions = "Subscriptions"
    case playlists = "Playlists"
    case live = "Live"
    case search = "Search"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .subscriptions: return "play.square.stack.fill"
        case .playlists: return "list.bullet.rectangle.fill"
        case .live: return "dot.radiowaves.left.and.right"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        }
    }
}

struct MainView: View {
    @State private var selectedItem: NavigationItem = .home
    @StateObject private var playerViewModel = PlayerViewModel()
    @StateObject private var homeViewModel = HomeViewModel()
    @StateObject private var subscriptionsViewModel = SubscriptionsViewModel()
    @StateObject private var playlistsViewModel = PlaylistsViewModel()
    @StateObject private var liveViewModel = LiveViewModel()
    @State private var isVideoFullscreen = false
    @State private var isTheaterPresented = false

    // Track actual window fullscreen state
    private let willEnterFullscreenPublisher = NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)
    private let willExitFullscreenPublisher = NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)

    var body: some View {
        ZStack {
            // Main app UI
            if !isTheaterPresented && !isVideoFullscreen {
                NavigationSplitView {
                    List(NavigationItem.allCases, selection: $selectedItem) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .tag(item)
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 180)
                } detail: {
                    contentView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaInset(edge: .bottom) {
                            if playerViewModel.currentVideo != nil {
                                MiniPlayerView(
                                    viewModel: playerViewModel,
                                    onTheater: { isTheaterPresented = true },
                                    onFullscreen: enterFullscreen
                                )
                            }
                        }
                }
            }

            // Theater mode
            if isTheaterPresented && !isVideoFullscreen {
                TheaterPlayerView(
                    viewModel: playerViewModel,
                    onExit: exitTheater,
                    onMinimize: exitTheater,
                    onEnterFullscreen: enterFullscreen
                )
                .transition(.opacity)
            }

            // Fullscreen mode - same layout as theater
            if isVideoFullscreen {
                TheaterPlayerView(
                    viewModel: playerViewModel,
                    onExit: exitFullscreen,
                    onMinimize: exitToMiniPlayer,
                    onEnterFullscreen: {}, // Not used when isFullscreen=true
                    isFullscreen: true
                )
            }
        }
        .environmentObject(playerViewModel)
        .onChange(of: playerViewModel.theaterRequested) { requested in
            if requested {
                isTheaterPresented = true
                playerViewModel.consumeTheaterRequest()
            }
        }
        .onChange(of: playerViewModel.currentVideo) { newValue in
            if newValue == nil {
                isTheaterPresented = false
                if isVideoFullscreen {
                    exitFullscreen()
                }
            }
        }
        .onReceive(willExitFullscreenPublisher) { _ in
            // User exited fullscreen via ESC or green button - sync our state
            if isVideoFullscreen {
                isVideoFullscreen = false
            }
        }
    }

    private func enterFullscreen() {
        isVideoFullscreen = true
        // Small delay to let SwiftUI update the view before going fullscreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApplication.shared.windows.first {
                if !window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                }
            }
        }
    }

    private func exitFullscreen() {
        // Exit fullscreen to theater view
        if let window = NSApplication.shared.windows.first {
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            } else {
                isVideoFullscreen = false
            }
        }
        // State will be updated by willExitFullscreenPublisher notification
        // Theater mode stays active
        isTheaterPresented = true
    }

    private func exitToMiniPlayer() {
        // Exit all the way to mini player
        isTheaterPresented = false
        if isVideoFullscreen {
            if let window = NSApplication.shared.windows.first {
                if window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                }
            }
        }
    }

    private func exitTheater() {
        isTheaterPresented = false
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedItem {
        case .home:
            HomeView(viewModel: homeViewModel)
        case .subscriptions:
            SubscriptionsView(viewModel: subscriptionsViewModel)
        case .playlists:
            PlaylistsView(viewModel: playlistsViewModel)
        case .live:
            LiveView(viewModel: liveViewModel)
        case .search:
            SearchView()
        case .settings:
            SettingsView()
        }
    }
}

struct QualityPickerView: View {
    @ObservedObject var viewModel: PlayerViewModel
    var showsText: Bool = true
    var usesDarkBackground: Bool = true

    private var bestAvailable: VideoFormatOption? {
        viewModel.availableFormats
            .filter { $0.id != VideoFormatOption.auto.id }
            .max { lhs, rhs in
                let lhsHeight = lhs.height ?? 0
                let rhsHeight = rhs.height ?? 0
                if lhsHeight != rhsHeight {
                    return lhsHeight < rhsHeight
                }
                let lhsFps = Int(lhs.fps?.rounded() ?? 0)
                let rhsFps = Int(rhs.fps?.rounded() ?? 0)
                return lhsFps < rhsFps
            }
    }

    private var displayQuality: String {
        if viewModel.selectedFormat.id == VideoFormatOption.auto.id, let bestAvailable {
            return "Auto \(bestAvailable.shortLabel)"
        }
        return viewModel.selectedFormat.shortLabel
    }

    private var explicitFormats: [VideoFormatOption] {
        viewModel.availableFormats.filter { $0.id != VideoFormatOption.auto.id }
    }

    var body: some View {
        Menu {
            Button(action: {
                viewModel.setFormat(.auto)
            }) {
                menuRow(
                    title: "Auto (Best available)",
                    subtitle: nil,
                    isSelected: viewModel.selectedFormat.id == VideoFormatOption.auto.id
                )
            }

            if !explicitFormats.isEmpty {
                Divider()
            }

            ForEach(explicitFormats) { format in
                Button(action: {
                    viewModel.setFormat(format)
                }) {
                    menuRow(
                        title: format.label,
                        subtitle: nil,
                        isSelected: format.id == viewModel.selectedFormat.id
                    )
                }
            }
        } label: {
            if showsText {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.subheadline)
                    Text("Quality")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                    Text(displayQuality)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(usesDarkBackground ? Color.black.opacity(0.4) : Color.clear)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(usesDarkBackground ? 0.25 : 0.15), lineWidth: 1)
            )
            .clipShape(Capsule())
            .fixedSize()
            } else {
                // Icon-only mode - single gear icon
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(usesDarkBackground ? Color.black.opacity(0.4) : Color.clear)
                    .clipShape(Circle())
            }
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private func menuRow(title: String, subtitle: String?, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }
}

struct PlaybackScrubber: View {
    @ObservedObject var viewModel: PlayerViewModel
    var textColor: Color = .white.opacity(0.8)

    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: {
                        isScrubbing ? scrubValue : min(viewModel.currentTime, max(viewModel.duration, 1))
                    },
                    set: { newValue in
                        scrubValue = newValue
                    }
                ),
                in: 0...max(viewModel.duration, 1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        viewModel.seek(to: scrubValue)
                    }
                }
            )
            .tint(.white)

            HStack {
                Text(formatTime(isScrubbing ? scrubValue : viewModel.currentTime))
                Spacer()
                Text(formatTime(viewModel.duration))
            }
            .font(.caption)
            .foregroundColor(textColor)
        }
        .onAppear {
            scrubValue = viewModel.currentTime
        }
        .onChange(of: viewModel.currentTime) { newValue in
            if !isScrubbing {
                scrubValue = newValue
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct TheaterPlayerView: View {
    @ObservedObject var viewModel: PlayerViewModel
    var onExit: () -> Void
    var onMinimize: () -> Void
    var onEnterFullscreen: () -> Void
    var isFullscreen: Bool = false

    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Mouse tracking layer - always present for hover detection
            MouseTrackingView {
                showControlsTemporarily(extend: false)
            }
            .ignoresSafeArea()

            if let player = viewModel.player {
                AVPlayerViewRepresentable(player: player)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .onTapGesture {
                        onEnterFullscreen()
                    }
            }

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.4)
                    .progressViewStyle(.circular)
            } else if let error = viewModel.error {
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .padding()
            }

            if let message = viewModel.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .transition(.opacity)
            }

            // Show controls when hovering OR when loading
            if showControls || viewModel.isLoading {
                VStack {
                    // Top bar
                    HStack {
                        Button(action: onMinimize) {
                            Image(systemName: "chevron.left")
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)

                        if let video = viewModel.currentVideo {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(video.title)
                                    .font(.title)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(video.channel)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.75))
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        // Gear in top right
                        QualityPickerView(viewModel: viewModel, showsText: false, usesDarkBackground: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [.black.opacity(0.75), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Spacer()

                    // Bottom controls
                    VStack(spacing: 12) {
                        PlaybackScrubber(viewModel: viewModel)

                        HStack(spacing: 28) {
                            Button(action: { Task { await viewModel.playPreviousVideo() } }) {
                                Image(systemName: "backward.end.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                            .disabled(!viewModel.hasPreviousVideo)
                            .opacity(viewModel.hasPreviousVideo ? 1.0 : 0.3)

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

                            Button(action: { Task { await viewModel.playNextVideo() } }) {
                                Image(systemName: "forward.end.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                            .disabled(!viewModel.hasNextVideo)
                            .opacity(viewModel.hasNextVideo ? 1.0 : 0.3)

                            Spacer()

                            if let position = viewModel.queuePosition {
                                Text(position)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 8)
                            }

                            Text(viewModel.displayQualityLabel)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())

                            Button(action: onMinimize) {
                                Image(systemName: "chevron.down")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                            .help("Minimize to mini player")

                            Button(action: isFullscreen ? onExit : onEnterFullscreen) {
                                Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                            .help(isFullscreen ? "Exit fullscreen" : "Enter fullscreen")
                        }
                        .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )
                }
                .transition(.opacity)
            }

        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.statusMessage)
        .onAppear {
            showControlsTemporarily(extend: true)
        }
        .onExitCommand {
            onMinimize()
        }
    }

    private func showControlsTemporarily(extend: Bool) {
        if !showControls {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls = true
            }
            scheduleHideControls()
        } else if extend {
            scheduleHideControls()
        }
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    // Don't hide controls while loading
                    if !viewModel.isLoading {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showControls = false
                        }
                    }
                }
            }
        }
    }
}

struct MiniPlayerView: View {
    @ObservedObject var viewModel: PlayerViewModel
    var onTheater: () -> Void
    var onFullscreen: () -> Void

    var body: some View {
        if let video = viewModel.currentVideo {
            VStack(spacing: 6) {
                MiniProgressBar(viewModel: viewModel)

                HStack(spacing: 12) {
                    Button(action: onTheater) {
                        HStack(spacing: 10) {
                            CachedAsyncImage(url: video.thumbnailURL) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color.gray.opacity(0.3)
                            }
                            .frame(width: 72, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Now Playing")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(video.title)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(video.channel)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: 240, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    HStack(spacing: 12) {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Button(action: { viewModel.togglePlayback() }) {
                                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: onTheater) {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.plain)

                        Button(action: onFullscreen) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                        .buttonStyle(.plain)

                        Button(action: { viewModel.stop() }) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider()
            }
        }
    }
}

struct MiniProgressBar: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        let progress = viewModel.duration > 0 ? min(viewModel.currentTime / viewModel.duration, 1) : 0
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 2)
    }
}

struct DownloadProgressView: View {
    let progress: Double
    let speed: String
    let videoTitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Downloading HD Video")
                .font(.headline)

            Text(videoTitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)

                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if !speed.isEmpty {
                        Text(speed)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct FullscreenPlayerView: View {
    @ObservedObject var viewModel: PlayerViewModel
    var onExit: () -> Void

    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video player with mouse tracking
            if let player = viewModel.player {
                MouseTrackingView {
                    showControlsTemporarily(extend: false)
                }
                .background(
                    AVPlayerViewRepresentable(player: player)
                )
                .ignoresSafeArea()
                .onTapGesture(count: 2) {
                    onExit()
                }
                .onTapGesture(count: 1) {
                    showControlsTemporarily(extend: true)
                }
            }

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.4)
                    .progressViewStyle(.circular)
            }

            if let message = viewModel.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .transition(.opacity)
            }

            // Controls overlay
            if showControls {
                VStack {
                    // Top bar - gear in top right
                    HStack {
                        Spacer()
                        QualityPickerView(viewModel: viewModel, showsText: false, usesDarkBackground: true)
                    }
                    .padding(20)

                    Spacer()

                    // Bottom control bar
                    VStack(spacing: 12) {
                        // Video title
                        if let video = viewModel.currentVideo {
                            Text(video.title)
                                .font(.title)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .shadow(radius: 2)
                        }

                        PlaybackScrubber(viewModel: viewModel)

                        // Controls row
                        HStack(spacing: 32) {
                            Button(action: { Task { await viewModel.playPreviousVideo() } }) {
                                Image(systemName: "backward.end.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                            .disabled(!viewModel.hasPreviousVideo)
                            .opacity(viewModel.hasPreviousVideo ? 1.0 : 0.3)

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

                            Button(action: { Task { await viewModel.playNextVideo() } }) {
                                Image(systemName: "forward.end.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                            .disabled(!viewModel.hasNextVideo)
                            .opacity(viewModel.hasNextVideo ? 1.0 : 0.3)

                            Spacer()

                            if let position = viewModel.queuePosition {
                                Text(position)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 8)
                            }

                            Text(viewModel.displayQualityLabel)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())

                            Button(action: onExit) {
                                Image(systemName: "arrow.down.right.and.arrow.up.left")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                            .help("Exit fullscreen")
                        }
                        .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )
                }
                .transition(.opacity)
            }

        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.statusMessage)
        .onAppear {
            showControlsTemporarily(extend: true)
        }
        .onExitCommand {
            onExit()
        }
    }

    private func showControlsTemporarily(extend: Bool) {
        if !showControls {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls = true
            }
            scheduleHideControls()
        } else if extend {
            scheduleHideControls()
        }
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showControls = false
                    }
                }
            }
        }
    }
}

// Track mouse movement for showing controls
struct MouseTrackingView: NSViewRepresentable {
    var onMouseMoved: () -> Void

    func makeNSView(context: Context) -> MouseTrackingNSView {
        let view = MouseTrackingNSView()
        view.onMouseMoved = onMouseMoved
        return view
    }

    func updateNSView(_ nsView: MouseTrackingNSView, context: Context) {
        nsView.onMouseMoved = onMouseMoved
    }

    class MouseTrackingNSView: NSView {
        var onMouseMoved: (() -> Void)?
        var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea {
                removeTrackingArea(existing)
            }
            trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea!)
        }

        override func mouseMoved(with event: NSEvent) {
            onMouseMoved?()
        }
    }
}

// Native AVPlayer view for better fullscreen performance
struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

#Preview {
    MainView()
}
