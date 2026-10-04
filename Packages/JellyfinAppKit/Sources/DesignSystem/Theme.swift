#if os(tvOS)
public import SwiftUI

/// A complete visual theme. Themes are the *only* thing the app sells:
/// playback, decoding and every feature are free forever.
public struct Theme: Identifiable, Hashable, Sendable {
    public enum FocusStyle: String, Sendable, Hashable { case lift, glow }

    public let id: String
    public let name: String
    public let tagline: String
    public let isPremium: Bool
    public let colorScheme: ColorScheme

    public let backgroundTop: Color
    public let backgroundBottom: Color
    public let surface: Color
    public let accent: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let progress: Color
    public let cardCornerRadius: CGFloat
    public let focusStyle: FocusStyle
    /// Grid section in the theme picker.
    public var family: String = "Signature"

    public var backgroundGradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Returns a copy with a different accent (the "custom accent" option).
    public func withAccent(_ color: Color) -> Theme {
        Theme(id: id, name: name, tagline: tagline, isPremium: isPremium, colorScheme: colorScheme, backgroundTop: backgroundTop, backgroundBottom: backgroundBottom, surface: surface, accent: color, primaryText: primaryText, secondaryText: secondaryText, progress: color, cardCornerRadius: cardCornerRadius, focusStyle: focusStyle, family: family)
    }
}

extension Theme {
    // Free
    public static let abyss = Theme(
        id: "abyss", name: "Abyss", tagline: "Deep water, bright edges.", isPremium: false, colorScheme: .dark,
        backgroundTop: Color(red: 0.03, green: 0.07, blue: 0.12), backgroundBottom: Color(red: 0.01, green: 0.02, blue: 0.04),
        surface: Color(red: 0.10, green: 0.15, blue: 0.22), accent: Color(red: 0.00, green: 0.80, blue: 0.85),
        primaryText: .white, secondaryText: Color(white: 0.68), progress: Color(red: 0.00, green: 0.80, blue: 0.85),
        cardCornerRadius: 14, focusStyle: .lift
    )

    public static let midnight = Theme(
        id: "midnight", name: "Midnight", tagline: "True black for OLED.", isPremium: false, colorScheme: .dark,
        backgroundTop: .black, backgroundBottom: .black,
        surface: Color(white: 0.10), accent: Color(red: 0.55, green: 0.42, blue: 1.0),
        primaryText: .white, secondaryText: Color(white: 0.6), progress: Color(red: 0.55, green: 0.42, blue: 1.0),
        cardCornerRadius: 12, focusStyle: .lift
    )

    // Premium
    public static let aurora = Theme(
        id: "aurora", name: "Aurora", tagline: "Northern lights after dark.", isPremium: true, colorScheme: .dark,
        backgroundTop: Color(red: 0.05, green: 0.12, blue: 0.14), backgroundBottom: Color(red: 0.10, green: 0.04, blue: 0.16),
        surface: Color(red: 0.12, green: 0.18, blue: 0.22), accent: Color(red: 0.40, green: 1.0, blue: 0.70),
        primaryText: .white, secondaryText: Color(white: 0.72), progress: Color(red: 0.40, green: 1.0, blue: 0.70),
        cardCornerRadius: 20, focusStyle: .glow
    )

    public static let ember = Theme(
        id: "ember", name: "Ember", tagline: "Warm, like a projector bulb.", isPremium: true, colorScheme: .dark,
        backgroundTop: Color(red: 0.14, green: 0.06, blue: 0.03), backgroundBottom: Color(red: 0.05, green: 0.02, blue: 0.01),
        surface: Color(red: 0.22, green: 0.12, blue: 0.08), accent: Color(red: 1.0, green: 0.55, blue: 0.20),
        primaryText: Color(red: 1.0, green: 0.96, blue: 0.92), secondaryText: Color(red: 0.85, green: 0.72, blue: 0.62), progress: Color(red: 1.0, green: 0.55, blue: 0.20),
        cardCornerRadius: 10, focusStyle: .glow
    )

    public static let paper = Theme(
        id: "paper", name: "Paper", tagline: "A light theme for daytime rooms.", isPremium: true, colorScheme: .light,
        backgroundTop: Color(red: 0.96, green: 0.95, blue: 0.93), backgroundBottom: Color(red: 0.88, green: 0.87, blue: 0.85),
        surface: Color(red: 0.82, green: 0.81, blue: 0.79), accent: Color(red: 0.85, green: 0.15, blue: 0.20),
        primaryText: Color(white: 0.08), secondaryText: Color(white: 0.35), progress: Color(red: 0.85, green: 0.15, blue: 0.20),
        cardCornerRadius: 6, focusStyle: .lift
    )

    public static let mono = Theme(
        id: "mono", name: "Mono", tagline: "Monochrome, editorial.", isPremium: true, colorScheme: .dark,
        backgroundTop: Color(white: 0.09), backgroundBottom: Color(white: 0.02),
        surface: Color(white: 0.16), accent: .white,
        primaryText: .white, secondaryText: Color(white: 0.55), progress: .white,
        cardCornerRadius: 0, focusStyle: .lift
    )

    public static let signature: [Theme] = [.abyss, .midnight, .aurora, .ember, .paper, .mono]
    public static let all: [Theme] = signature + catalog

    /// Picker sections, in display order.
    public static var families: [(name: String, themes: [Theme])] {
        var order: [String] = []
        for t in all where !order.contains(t.family) { order.append(t.family) }
        return order.map { name in (name, all.filter { $0.family == name }) }
    }

    public static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? .abyss }

    /// Accent choices for the premium "custom accent" option.
    public static let accentPalette: [Color] = [
        Color(red: 0.00, green: 0.80, blue: 0.85), Color(red: 0.55, green: 0.42, blue: 1.0), Color(red: 1.0, green: 0.27, blue: 0.40),
        Color(red: 1.0, green: 0.55, blue: 0.20), Color(red: 1.0, green: 0.84, blue: 0.20), Color(red: 0.40, green: 1.0, blue: 0.70),
        Color(red: 0.30, green: 0.60, blue: 1.0), .white,
    ]
}

extension EnvironmentValues {
    @Entry public var theme: Theme = .abyss
}

/// Layout metrics in tvOS points (1920×1080 canvas). Card sizes are chosen so
/// rows show a whole number of cards inside the 80 pt title-safe margins.
public enum Layout {
    public static let horizontalMargin: CGFloat = 80
    public static let shelfSpacing: CGFloat = 36
    public static let cardSpacing: CGFloat = 40
    public static let posterWidth: CGFloat = 228          // 7 per row
    public static let landscapeWidth: CGFloat = 400       // 4 per row
    public static let castWidth: CGFloat = 160
    public static let squareWidth: CGFloat = 300          // audiobook covers, 5 per row
}
#endif
