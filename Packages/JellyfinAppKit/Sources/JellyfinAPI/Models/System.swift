public import Foundation

public struct PublicSystemInfo: Codable, Sendable, Hashable {
    public var id: String?
    public var serverName: String?
    public var version: String?
    public var productName: String?
    public var localAddress: String?
    public var startupWizardCompleted: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "Id", serverName = "ServerName", version = "Version", productName = "ProductName"
        case localAddress = "LocalAddress", startupWizardCompleted = "StartupWizardCompleted"
    }

    public init(id: String?, serverName: String?, version: String?) {
        self.id = id
        self.serverName = serverName
        self.version = version
    }

    /// Minimum server this app talks to. We use 10.11 endpoints and fields
    /// (e.g. `AudioSpatialFormat`, `/UserItems/*`, MediaSegments) without fallbacks.
    public static let minimumVersion = ServerVersion(10, 11, 0)

    public var parsedVersion: ServerVersion? { version.flatMap(ServerVersion.init) }
    public var isSupported: Bool { (parsedVersion ?? ServerVersion(0, 0, 0)) >= Self.minimumVersion }
}

public struct ServerVersion: Comparable, Sendable, Hashable, CustomStringConvertible {
    public var major: Int, minor: Int, patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ string: String) {
        let parts = string.split(separator: ".").compactMap { Int($0.prefix { $0.isNumber }) }
        guard parts.count >= 2 else { return nil }
        self.init(parts[0], parts[1], parts.count > 2 ? parts[2] : 0)
    }

    public static func < (a: Self, b: Self) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

public struct UserDto: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String?
    public var serverId: String?
    public var primaryImageTag: String?
    public var hasPassword: Bool?
    public var hasConfiguredPassword: Bool?
    public var policy: UserPolicy?
    public var configuration: UserConfiguration?
    public var lastLoginDate: Date?
    public var lastActivityDate: Date?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", serverId = "ServerId", primaryImageTag = "PrimaryImageTag"
        case hasPassword = "HasPassword", hasConfiguredPassword = "HasConfiguredPassword", policy = "Policy"
        case configuration = "Configuration", lastLoginDate = "LastLoginDate", lastActivityDate = "LastActivityDate"
    }

    public init(id: String, name: String?) {
        self.id = id
        self.name = name
    }
}

public struct UserPolicy: Codable, Sendable, Hashable {
    public var isAdministrator: Bool?
    public var enableMediaPlayback: Bool?
    public var enableVideoPlaybackTranscoding: Bool?
    public var enablePlaybackRemuxing: Bool?
    public var remoteClientBitrateLimit: Int?

    enum CodingKeys: String, CodingKey {
        case isAdministrator = "IsAdministrator", enableMediaPlayback = "EnableMediaPlayback"
        case enableVideoPlaybackTranscoding = "EnableVideoPlaybackTranscoding"
        case enablePlaybackRemuxing = "EnablePlaybackRemuxing", remoteClientBitrateLimit = "RemoteClientBitrateLimit"
    }
}

public struct UserConfiguration: Codable, Sendable, Hashable {
    public var audioLanguagePreference: String?
    public var subtitleLanguagePreference: String?
    public var playDefaultAudioTrack: Bool?
    public var subtitleMode: String?   // Default, Always, OnlyForced, None, Smart
    public var enableNextEpisodeAutoPlay: Bool?
    public var rememberAudioSelections: Bool?
    public var rememberSubtitleSelections: Bool?

    enum CodingKeys: String, CodingKey {
        case audioLanguagePreference = "AudioLanguagePreference", subtitleLanguagePreference = "SubtitleLanguagePreference"
        case playDefaultAudioTrack = "PlayDefaultAudioTrack", subtitleMode = "SubtitleMode"
        case enableNextEpisodeAutoPlay = "EnableNextEpisodeAutoPlay", rememberAudioSelections = "RememberAudioSelections"
        case rememberSubtitleSelections = "RememberSubtitleSelections"
    }
}

public struct AuthenticationResult: Codable, Sendable {
    public var user: UserDto
    public var accessToken: String
    public var serverId: String?

    enum CodingKeys: String, CodingKey { case user = "User", accessToken = "AccessToken", serverId = "ServerId" }
}

public struct QuickConnectState: Codable, Sendable, Hashable {
    public var authenticated: Bool
    public var secret: String
    public var code: String
    public var deviceId: String?

    enum CodingKeys: String, CodingKey { case authenticated = "Authenticated", secret = "Secret", code = "Code", deviceId = "DeviceId" }
}
