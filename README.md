# Native YouTube App for Apple Silicon Mac

A lightweight, native macOS YouTube client built with SwiftUI. Designed specifically for Apple Silicon Macs, it provides a clean, distraction-free way to browse and watch YouTube without the overhead of a web browser.

| ![Subscriptions](screenshots/Subscriptions.png) | ![Video](screenshots/Video.png) |
|:---:|:---:|
| Subscriptions | Video Player |

## Features

### Browse YouTube Natively
- **Home Feed** - Personalized recommendations
- **Subscriptions** - Latest from channels you follow
- **Playlists** - Your saved playlists with full playback support
- **Live** - Discover live streams
- **Search** - Find any video

### Smart Video Playback

The player uses several techniques to deliver the best experience:

- **Instant Start** - Videos begin playing immediately using a fast muxed stream, then seamlessly upgrade to higher quality in the background without interrupting playback
- **Separate Audio/Video Streams** - Combines the highest quality video and audio tracks (like DASH), enabling resolutions and bitrates not available in pre-muxed formats
- **Hardware Accelerated** - Native AVPlayer with support for H.264, H.265 (HEVC), and AV1 codecs
- **Quality Selection** - Choose from all available resolutions up to 4K. The UI shows transitions like `720p >> 1080p` when switching quality
- **Playlist Preloading** - The next video in a playlist is fetched in the background for instant advancement

### Viewing Modes
- **Mini Player** - Continues playing at the bottom while you browse
- **Theater Mode** - Expanded view with video info and controls
- **Fullscreen** - Immersive viewing with auto-hiding controls

### Audio Options
- Prefer original audio tracks over dubbed versions
- Set a preferred audio language

### Performance
- Two-tier thumbnail cache (memory + disk) with 7-day retention
- Format metadata caching to speed up repeat plays
- Stream URL caching to avoid redundant network calls

## Requirements

- macOS 13.0+
- Apple Silicon Mac (M1/M2/M3/M4)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) installed via Homebrew
- Chrome, Firefox, or Safari (for cookie-based authentication)

## Installation

### 1. Install yt-dlp

```bash
brew install yt-dlp
```

### 2. Sign in to YouTube

Open your browser and sign in to YouTube. The app reads your browser cookies to access subscriptions and playlists.

### 3. Build & Run

```bash
open YouTubeApp.xcodeproj
```

Press `Cmd + R` to build and run.

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Space` | Play / Pause |
| `←` | Skip back 10s |
| `→` | Skip forward 10s |
| `N` | Next video in playlist |
| `P` | Previous video in playlist |

## How It Works

The app uses [yt-dlp](https://github.com/yt-dlp/yt-dlp) to:
1. Fetch video metadata and thumbnails from YouTube feeds
2. Extract direct stream URLs for playback
3. Access your subscriptions/playlists via browser cookies

Videos play through native `AVPlayer`. For higher quality playback, separate video and audio streams are combined using `AVMutableComposition`, which enables quality levels that aren't available in YouTube's pre-muxed formats.

## Project Structure

```
YouTubeApp/
├── Models/           # Video, Playlist, Channel data types
├── Services/
│   ├── YTDLPService          # yt-dlp integration
│   ├── ThumbnailCacheService # Two-tier image cache
│   ├── FormatCacheService    # Video format metadata cache
│   └── SettingsService       # User preferences
├── ViewModels/       # SwiftUI view models
└── Views/
    ├── MainView              # App shell with sidebar
    ├── VideoPlayerView       # Theater & fullscreen player
    └── Components/           # Reusable UI components
```

## License

MIT
