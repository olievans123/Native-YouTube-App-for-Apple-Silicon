import Foundation

class SettingsService: ObservableObject {
    static let shared = SettingsService()

    private let defaults = UserDefaults.standard

    // Keys
    private let preferredQualityKey = "preferredQuality"
    private let preferredAudioLanguageKey = "preferredAudioLanguage"
    private let disableDubbedAudioKey = "disableDubbedAudio"

    @Published var preferredQuality: PreferredQuality {
        didSet { defaults.set(preferredQuality.rawValue, forKey: preferredQualityKey) }
    }

    @Published var preferredAudioLanguage: String {
        didSet { defaults.set(preferredAudioLanguage, forKey: preferredAudioLanguageKey) }
    }

    @Published var disableDubbedAudio: Bool {
        didSet { defaults.set(disableDubbedAudio, forKey: disableDubbedAudioKey) }
    }

    init() {
        let qualityRaw = defaults.string(forKey: preferredQualityKey) ?? PreferredQuality.auto.rawValue
        self.preferredQuality = PreferredQuality(rawValue: qualityRaw) ?? .auto

        // Empty string means "original/native" audio
        self.preferredAudioLanguage = defaults.string(forKey: preferredAudioLanguageKey) ?? ""

        // Default to disabling dubbed audio (prefer original)
        self.disableDubbedAudio = defaults.object(forKey: disableDubbedAudioKey) as? Bool ?? true
    }
}

enum PreferredQuality: String, CaseIterable, Identifiable {
    case auto = "auto"
    case quality2160p = "2160p"
    case quality1080p = "1080p"
    case quality720p = "720p"
    case quality480p = "480p"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto (Best available)"
        case .quality2160p: return "4K (2160p)"
        case .quality1080p: return "1080p"
        case .quality720p: return "720p"
        case .quality480p: return "480p"
        }
    }

    var maxHeight: Int? {
        switch self {
        case .auto: return nil
        case .quality2160p: return 2160
        case .quality1080p: return 1080
        case .quality720p: return 720
        case .quality480p: return 480
        }
    }
}
