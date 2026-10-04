public import Foundation

/// The single source of truth for user-facing naming. Rebranding = change
/// `APP_DISPLAY_NAME` / `PRODUCT_BUNDLE_IDENTIFIER` in project.yml; nothing in
/// code mentions the product name directly.
public enum Brand {
    /// Shown in UI ("Welcome to …") and sent to Jellyfin as the client name,
    /// which appears in the server's dashboard under Devices / Activity.
    public static let displayName: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "Bumper"

    public static let version: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"

    public static let build: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

    public static let bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.kristianfreeman.bumper"

    public static let sourceCodeURL = URL(string: "https://github.com/kristianfreeman/bumper")!
}

/// The business rules in one place.
public enum Monetization {
    /// Every theme is unlocked for everyone until the real in-app purchase
    /// ships. Flip to `false` before an App Store release.
    public static let themesUnlockedForEveryone = true
}
