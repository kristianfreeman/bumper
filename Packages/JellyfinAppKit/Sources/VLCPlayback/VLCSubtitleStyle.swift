#if os(tvOS)
public import AppCore

/// The user's subtitle preset, expressed as VLC text-renderer options — so
/// plain-text subtitles (SRT, VTT, …) look the same under VLCKit as the
/// player's own overlay does under AVPlayer. ASS keeps its own styling and
/// PGS is drawn as authored.
public struct VLCSubtitleStyle: Sendable, Equatable {
    public let options: [String]

    public init(_ style: SubtitleStyle, scale: Double, font: SubtitleFont = .system) {
        // Relative size: VLC divides the video height by this, so smaller is bigger.
        var o = ["--freetype-rel-fontsize=\(Int((16 / max(scale, 0.5)).rounded()))"]
        if let family = font.family { o.append("--freetype-font=\(family)") }
        let white = 0xFFFFFF, black = 0x000000, yellow = 0xFFE033
        switch style {
        case .classic:
            o += ["--freetype-color=\(white)", "--freetype-bold", "--freetype-outline-thickness=2",
                  "--freetype-shadow-opacity=200", "--freetype-shadow-distance=0.04"]
        case .outline:
            o += ["--freetype-color=\(white)", "--freetype-bold", "--freetype-outline-thickness=6",
                  "--freetype-outline-color=\(black)", "--freetype-shadow-opacity=0"]
        case .boxed:
            o += ["--freetype-color=\(white)", "--freetype-outline-thickness=0", "--freetype-shadow-opacity=0",
                  "--freetype-background-color=\(black)", "--freetype-background-opacity=184"]
        case .yellow:
            o += ["--freetype-color=\(yellow)", "--freetype-bold", "--freetype-outline-thickness=6",
                  "--freetype-outline-color=\(black)", "--freetype-shadow-opacity=0"]
        case .light:
            o += ["--freetype-color=\(white)", "--freetype-outline-thickness=0",
                  "--freetype-shadow-opacity=150", "--freetype-shadow-distance=0.02"]
        }
        options = o
    }
}
#endif
