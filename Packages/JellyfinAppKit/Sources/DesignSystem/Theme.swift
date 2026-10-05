public import SwiftUI
#if os(iOS)
import UIKit
#endif

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
    /// The brand's own (BrandTheme.swift, from the brand kit). Cyan is for
    /// focus, progress and what's playing only; the mark's red plate is
    /// never a theme colour.
    public static let bumper = Theme(
        id: "bumper", name: "Bumper Dark", tagline: "Keeps things playing.", isPremium: false, colorScheme: .dark,
        backgroundTop: BumperBrand.Palette.soot, backgroundBottom: BumperBrand.Palette.ink,
        surface: BumperBrand.Palette.graphite, accent: BumperBrand.Palette.signal,
        primaryText: BumperBrand.Palette.paper, secondaryText: Color(red: 0.667, green: 0.643, blue: 0.592),   // #AAA497, 7.3:1 on soot
        progress: BumperBrand.Palette.signal,
        cardCornerRadius: 16, focusStyle: .lift
    )

    /// Bumper on paper (the kit's BumperBrand.Light): ink text, and the
    /// signal darkened to 4.5 : 1 on the deepest ground, same cyan hue.
    public static let bumperLight = Theme(
        id: "bumper-light", name: "Bumper Light", tagline: "Paper and ink.", isPremium: false, colorScheme: .light,
        backgroundTop: BumperBrand.Light.ground, backgroundBottom: BumperBrand.Light.groundDeep,
        surface: BumperBrand.Light.surface, accent: BumperBrand.Light.signal,
        primaryText: BumperBrand.Light.text, secondaryText: BumperBrand.Light.quiet,
        progress: BumperBrand.Light.signal,
        cardCornerRadius: 16, focusStyle: .lift
    )

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

    public static let signature: [Theme] = [.bumper, .bumperLight, .abyss, .midnight, .aurora, .ember, .paper, .mono]
    public static let all: [Theme] = signature + catalog

    /// Picker sections, in display order.
    public static var families: [(name: String, themes: [Theme])] {
        var order: [String] = []
        for t in all where !order.contains(t.family) { order.append(t.family) }
        return order.map { name in (name, all.filter { $0.family == name }) }
    }

    public static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? .bumper }

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
/// Sizes per device: the TV's at ten feet, the Mac's and iPad's at a desk or
/// on the sofa, the iPhone's in hand.
public enum Layout {
    public enum Device: Sendable { case tv, mac, pad, phone }

    public static let device: Device = {
        #if os(tvOS)
        .tv
        #elseif os(macOS)
        .mac
        #else
        MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone }
        #endif
    }()

    private static func pick(tv: CGFloat, mac: CGFloat, pad: CGFloat, phone: CGFloat) -> CGFloat {
        switch device { case .tv: tv; case .mac: mac; case .pad: pad; case .phone: phone }
    }

    public static let horizontalMargin = pick(tv: 80, mac: 40, pad: 32, phone: 16)
    public static let shelfSpacing = pick(tv: 36, mac: 28, pad: 28, phone: 20)
    public static let cardSpacing = pick(tv: 40, mac: 24, pad: 20, phone: 12)
    public static let posterWidth = pick(tv: 228, mac: 160, pad: 150, phone: 110)          // TV: 7 per row
    public static let landscapeWidth = pick(tv: 400, mac: 300, pad: 300, phone: 260)       // TV: 4 per row
    public static let castWidth = pick(tv: 160, mac: 110, pad: 110, phone: 84)
    public static let squareWidth = pick(tv: 300, mac: 200, pad: 200, phone: 150)          // audiobook covers
    /// Page titles ("Good evening, Kristian.", "Settings") and smaller ones (collection pages).
    public static let pageTitle = pick(tv: 64, mac: 40, pad: 44, phone: 34)
    public static let pageTitleSmall = pick(tv: 56, mac: 34, pad: 38, phone: 30)
    public static let sectionTitle = pick(tv: 44, mac: 28, pad: 30, phone: 24)

    /// Pills (and other controls drawn for the TV) at this fraction of their TV size.
    public static let pillScale = pick(tv: 1, mac: 0.55, pad: 0.6, phone: 0.55)

    /// The narrowest a card may get before a grid drops a column.
    public static let landscapeMin = pick(tv: 360, mac: 240, pad: 220, phone: 150)
    public static let posterMin = pick(tv: 220, mac: 140, pad: 130, phone: 100)

    /// Columns for cards at least `minWidth` wide in `available`, at most `max`.
    public static func columns(_ available: CGFloat, minWidth: CGFloat, max: Int) -> Int {
        let n = Int((available + cardSpacing) / (minWidth + cardSpacing))
        return Swift.max(device == .phone ? 2 : 1, Swift.min(max, n))
    }

    /// The width of each of `columns` cards across `available`.
    public static func cardWidth(_ available: CGFloat, columns: Int) -> CGFloat {
        ((available - CGFloat(columns - 1) * cardSpacing) / CGFloat(columns)).rounded(.down)
    }
}
