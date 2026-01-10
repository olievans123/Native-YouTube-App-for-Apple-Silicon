import Foundation

class SettingsService: ObservableObject {
    static let shared = SettingsService()

    private let defaults = UserDefaults.standard

    // Keys
    private let preferredQualityKey = "preferredQuality"
    private let qualityStartModeKey = "qualityStartMode"
    private let preferredAudioLanguageKey = "preferredAudioLanguage"
    private let disableDubbedAudioKey = "disableDubbedAudio"
    private let cookiesBrowserKey = "cookiesBrowser"

    @Published var preferredQuality: PreferredQuality {
        didSet { defaults.set(preferredQuality.rawValue, forKey: preferredQualityKey) }
    }

    @Published var preferredAudioLanguage: String {
        didSet { defaults.set(preferredAudioLanguage, forKey: preferredAudioLanguageKey) }
    }

    @Published var qualityStartMode: QualityStartMode {
        didSet { defaults.set(qualityStartMode.rawValue, forKey: qualityStartModeKey) }
    }

    @Published var disableDubbedAudio: Bool {
        didSet { defaults.set(disableDubbedAudio, forKey: disableDubbedAudioKey) }
    }

    @Published var cookiesBrowser: CookiesBrowser {
        didSet { defaults.set(cookiesBrowser.rawValue, forKey: cookiesBrowserKey) }
    }

    init() {
        let qualityRaw = defaults.string(forKey: preferredQualityKey) ?? PreferredQuality.auto.rawValue
        self.preferredQuality = PreferredQuality(rawValue: qualityRaw) ?? .auto

        let startModeRaw = defaults.string(forKey: qualityStartModeKey) ?? QualityStartMode.instantUpgrade.rawValue
        self.qualityStartMode = QualityStartMode(rawValue: startModeRaw) ?? .instantUpgrade

        // Empty string means "original/native" audio
        self.preferredAudioLanguage = defaults.string(forKey: preferredAudioLanguageKey) ?? ""

        // Default to disabling dubbed audio (prefer original)
        self.disableDubbedAudio = defaults.object(forKey: disableDubbedAudioKey) as? Bool ?? true

        let browserRaw = defaults.string(forKey: cookiesBrowserKey) ?? CookiesBrowser.auto.rawValue
        self.cookiesBrowser = CookiesBrowser(rawValue: browserRaw) ?? .auto
    }
}

enum CookiesBrowser: String, CaseIterable, Identifiable {
    case auto = "auto"
    case chrome = "chrome"
    case firefox = "firefox"
    case safari = "safari"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .chrome: return "Chrome"
        case .firefox: return "Firefox"
        case .safari: return "Safari"
        }
    }

    var ytDlpValue: String {
        switch self {
        case .auto: return "auto"
        case .chrome: return "chrome"
        case .firefox: return "firefox"
        case .safari: return "safari"
        }
    }

    static var autoFallbackOrder: [CookiesBrowser] {
        [.chrome, .safari, .firefox]
    }
}

enum QualityStartMode: String, CaseIterable, Identifiable {
    case instantUpgrade = "instantUpgrade"
    case waitForQuality = "waitForQuality"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .instantUpgrade:
            return "Instant start, then upgrade"
        case .waitForQuality:
            return "Wait for selected quality"
        }
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
