public import Foundation
public import Observation

/// Which backend plays an item. `.automatic` is right for almost everyone.
public enum EnginePreference: String, Codable, Sendable, CaseIterable, Identifiable {
    /// AVPlayer when the item meets its rules (MP4/MOV/HLS · H.264/HEVC ·
    /// AAC/AC-3/E-AC-3 · no subtitles or WebVTT), VLCKit for everything else.
    case automatic
    /// VLCKit for every direct-playable item (diagnostics).
    case vlc

    public var id: String { rawValue }
}

public enum SubtitleMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case serverDefault, always, forcedOnly, off
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .always: "On"
        case .serverDefault: "Server Default"
        case .forcedOnly: "Forced Only"
        case .off: "Off"
        }
    }
}

/// Text subtitle look. (Bitmap subtitles — PGS, VobSub — are drawn as authored.)
public enum SubtitleStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// White, soft shadow. Reads well on almost anything.
    case classic
    /// White with a crisp black edge — best over bright, busy scenes.
    case outline
    /// White on a dark box — maximum legibility.
    case boxed
    /// Yellow with an edge, the DVD-era favourite.
    case yellow
    /// Lighter weight, faint shadow — least intrusive.
    case light

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .classic: "Classic"
        case .outline: "Outline"
        case .boxed: "Boxed"
        case .yellow: "Yellow"
        case .light: "Light"
        }
    }
}

/// Typeface for text subtitles (SRT, WebVTT…). Styled ASS/SSA keeps the
/// fonts it was authored with, including ones embedded in the file.
public enum SubtitleFont: String, Codable, Sendable, CaseIterable, Identifiable {
    case system, helvetica, avenir, futura, times, courier

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "San Francisco"
        case .helvetica: "Helvetica Neue"
        case .avenir: "Avenir Next"
        case .futura: "Futura"
        case .times: "Times New Roman"
        case .courier: "Courier New"
        }
    }

    /// Font family both renderers look up (nil: the system font).
    public var family: String? { self == .system ? nil : title }
}

/// Text subtitle size presets (scale factor on the base size).
public enum SubtitleSize {
    public static let options: [(title: String, scale: Double)] = [("Small", 0.8), ("Medium", 1.0), ("Large", 1.2), ("Extra Large", 1.4)]
    public static func title(for scale: Double) -> String {
        options.min { abs($0.scale - scale) < abs($1.scale - scale) }?.title ?? "Medium"
    }
}

/// User preferences, persisted to UserDefaults. Each property writes through
/// on change; reads are plain stored-property reads (no defaults lookup on
/// hot paths).
@MainActor
@Observable
public final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    public var enginePreference: EnginePreference { didSet { save(enginePreference.rawValue, "playback.engine") } }
    /// Bits per second; nil = unlimited (LAN).
    public var maxBitrate: Int? { didSet { defaults.set(maxBitrate, forKey: "playback.maxBitrate") } }
    /// Match the TV's frame rate and dynamic range to the content.
    public var matchContent: Bool { didSet { save(matchContent, "playback.matchContent") } }
    /// Pass Dolby Atmos / multichannel bitstreams through when the receiver supports it.
    public var preferPassthrough: Bool { didSet { save(preferPassthrough, "playback.passthrough") } }
    public var subtitleMode: SubtitleMode { didSet { save(subtitleMode.rawValue, "subtitles.mode") } }
    public var subtitleScale: Double { didSet { save(subtitleScale, "subtitles.scale") } }
    public var subtitleStyle: SubtitleStyle { didSet { save(subtitleStyle.rawValue, "subtitles.style") } }
    public var subtitleFont: SubtitleFont { didSet { save(subtitleFont.rawValue, "subtitles.font") } }
    /// Audiobooks: voice speed (pitch kept) and Smart Speed (shorter silences).
    public var audiobookRate: Double { didSet { save(audiobookRate, "audiobooks.rate") } }
    public var smartSpeed: Bool { didSet { save(smartSpeed, "audiobooks.smartSpeed") } }
    public var autoplayNextEpisode: Bool { didSet { save(autoplayNextEpisode, "playback.autoplayNext") } }
    public var skipIntrosAutomatically: Bool { didSet { save(skipIntrosAutomatically, "playback.autoSkipIntro") } }
    /// Developer HUD with live perf metrics + budgets.
    public var showPerformanceHUD: Bool { didSet { save(showPerformanceHUD, "debug.perfHUD") } }
    public var themeId: String { didSet { save(themeId, "appearance.theme") } }
    /// Series theme songs on detail pages.
    public var playThemeMusic: Bool { didSet { save(playThemeMusic, "detail.themeMusic") } }
    public var themeMusicForMovies: Bool { didSet { save(themeMusicForMovies, "detail.themeMusicMovies") } }
    /// No theme on the server → Plex's public TV theme archive (by TVDB id).
    public var onlineThemeFallback: Bool { didSet { save(onlineThemeFallback, "detail.themeMusicOnline") } }
    /// Unwatched episodes: blurred stills, no descriptions.
    public var hideSpoilers: Bool { didSet { save(hideSpoilers, "browse.hideSpoilers") } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enginePreference = EnginePreference(rawValue: defaults.string(forKey: "playback.engine") ?? "") ?? .automatic
        maxBitrate = defaults.object(forKey: "playback.maxBitrate") as? Int
        matchContent = defaults.object(forKey: "playback.matchContent") as? Bool ?? true
        preferPassthrough = defaults.object(forKey: "playback.passthrough") as? Bool ?? true
        subtitleMode = SubtitleMode(rawValue: defaults.string(forKey: "subtitles.mode") ?? "") ?? .always
        subtitleScale = defaults.object(forKey: "subtitles.scale") as? Double ?? 1.0
        subtitleStyle = SubtitleStyle(rawValue: defaults.string(forKey: "subtitles.style") ?? "") ?? .classic
        subtitleFont = SubtitleFont(rawValue: defaults.string(forKey: "subtitles.font") ?? "") ?? .system
        audiobookRate = defaults.object(forKey: "audiobooks.rate") as? Double ?? 1.0
        smartSpeed = defaults.object(forKey: "audiobooks.smartSpeed") as? Bool ?? false
        autoplayNextEpisode = defaults.object(forKey: "playback.autoplayNext") as? Bool ?? true
        skipIntrosAutomatically = defaults.object(forKey: "playback.autoSkipIntro") as? Bool ?? false
        showPerformanceHUD = defaults.object(forKey: "debug.perfHUD") as? Bool ?? false
        themeId = defaults.string(forKey: "appearance.theme") ?? Self.defaultTheme
        playThemeMusic = defaults.object(forKey: "detail.themeMusic") as? Bool ?? true
        themeMusicForMovies = defaults.object(forKey: "detail.themeMusicMovies") as? Bool ?? false
        onlineThemeFallback = defaults.object(forKey: "detail.themeMusicOnline") as? Bool ?? true
        hideSpoilers = defaults.object(forKey: "browse.hideSpoilers") as? Bool ?? true
    }

    /// Bumper Dark, until someone picks another theme.
    public static let defaultTheme = "bumper"

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}
