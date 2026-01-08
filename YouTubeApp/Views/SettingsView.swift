import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsService.shared

    var body: some View {
        Form {
            Section("Video Quality") {
                Picker("Preferred Quality", selection: $settings.preferredQuality) {
                    ForEach(PreferredQuality.allCases) { quality in
                        Text(quality.label).tag(quality)
                    }
                }
                .pickerStyle(.inline)

                Text("Videos will play at this quality or the closest available option.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Audio") {
                Toggle("Disable dubbed audio tracks", isOn: $settings.disableDubbedAudio)

                Text("When enabled, the player will prefer the default/original track and avoid obvious dubs.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Preferred audio language (e.g., en)", text: $settings.preferredAudioLanguage)
                    .textFieldStyle(.roundedBorder)

                Text("Leave blank to prefer the default/original track.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }

                Link("yt-dlp Documentation", destination: URL(string: "https://github.com/yt-dlp/yt-dlp")!)
            }

            Section("Cache") {
                Button("Clear Thumbnail Cache") {
                    Task {
                        await ThumbnailCacheService.shared.clearCache()
                    }
                }

                Button("Clear Format Cache") {
                    Task {
                        await FormatCacheService.shared.clearCache()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(maxWidth: 600)
    }
}
