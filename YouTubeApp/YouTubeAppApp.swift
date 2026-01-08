import SwiftUI

@main
struct YouTubeAppApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Playback") {
                Button("Play/Pause") {
                    NotificationCenter.default.post(name: .togglePlayback, object: nil)
                }
                .keyboardShortcut(.space, modifiers: [])

                Divider()

                Button("Next Video") {
                    NotificationCenter.default.post(name: .playNextVideo, object: nil)
                }
                .keyboardShortcut("n", modifiers: [])

                Button("Previous Video") {
                    NotificationCenter.default.post(name: .playPreviousVideo, object: nil)
                }
                .keyboardShortcut("p", modifiers: [])

                Divider()

                Button("Skip Forward 10s") {
                    NotificationCenter.default.post(name: .seekForward, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                Button("Skip Back 10s") {
                    NotificationCenter.default.post(name: .seekBackward, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
            }
        }
    }
}

extension Notification.Name {
    static let togglePlayback = Notification.Name("togglePlayback")
    static let playNextVideo = Notification.Name("playNextVideo")
    static let playPreviousVideo = Notification.Name("playPreviousVideo")
    static let seekForward = Notification.Name("seekForward")
    static let seekBackward = Notification.Name("seekBackward")
}
