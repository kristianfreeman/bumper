public import SwiftUI

/// The premium catalogue: families of six, each theme defined by three
/// colours (background top/bottom, accent). Surfaces and text are derived so
/// every theme keeps the same contrast rules.
extension Theme {
    public static let catalog: [Theme] = [
        // OLED — true black, one vivid accent
        .make("obsidian", "Obsidian", "Black glass, red edge.", "OLED", 0x000000, 0x000000, 0xFF3B4E, radius: 12),
        .make("onyx", "Onyx", "Black and gold.", "OLED", 0x000000, 0x000000, 0xE8B931, radius: 12),
        .make("jet", "Jet", "Black with a green light.", "OLED", 0x000000, 0x000000, 0x30D158, radius: 12),
        .make("carbon", "Carbon", "Black and safety orange.", "OLED", 0x000000, 0x000000, 0xFF8A1F, radius: 8),
        .make("vanta", "Vanta", "Darker than dark.", "OLED", 0x000000, 0x000000, 0x4D8DFF, radius: 16),
        .make("eclipse", "Eclipse", "A corona of pink.", "OLED", 0x000000, 0x000000, 0xFF4FA3, radius: 16, focus: .glow),

        // Ocean
        .make("lagoon", "Lagoon", "Shallow turquoise water.", "Ocean", 0x06262B, 0x02100F, 0x2EE6D6),
        .make("reef", "Reef", "Coral over deep blue.", "Ocean", 0x071A33, 0x020814, 0xFF7A66, radius: 18),
        .make("tide", "Tide", "Moonlit high water.", "Ocean", 0x0B1830, 0x030712, 0x8FB8FF),
        .make("fjord", "Fjord", "Cold, still, clear.", "Ocean", 0x14202A, 0x070C11, 0x9ED8E8, radius: 10),
        .make("kelp", "Kelp", "Green light underwater.", "Ocean", 0x08201C, 0x020B09, 0x7BE495),
        .make("glacier", "Glacier", "Blue ice in shadow.", "Ocean", 0x0E2233, 0x050B12, 0xBDE8FF, radius: 20, focus: .glow),

        // Forest
        .make("moss", "Moss", "Soft green on stone.", "Forest", 0x141C12, 0x070A06, 0xA3D977),
        .make("pine", "Pine", "Evergreen at dusk.", "Forest", 0x0C1F17, 0x030A07, 0x4CC38A),
        .make("fern", "Fern", "Fresh growth.", "Forest", 0x10221A, 0x050C09, 0x8CF2B5, radius: 18),
        .make("sage", "Sage", "Muted, herbal, calm.", "Forest", 0x1A201B, 0x0A0D0B, 0xB7C9A8, radius: 10),
        .make("canopy", "Canopy", "Sun through leaves.", "Forest", 0x0F1E10, 0x040A04, 0xE6D35A),
        .make("lichen", "Lichen", "Grey-green and gold.", "Forest", 0x1B1D16, 0x0A0B08, 0xD4C36A, radius: 6),

        // Warm
        .make("sunset", "Sunset", "The last ten minutes of light.", "Warm", 0x2A0F1C, 0x0D0408, 0xFF8C5A, radius: 18, focus: .glow),
        .make("amber", "Amber", "Honey under a lamp.", "Warm", 0x1F1405, 0x0A0602, 0xFFB627),
        .make("terracotta", "Terracotta", "Fired clay.", "Warm", 0x24120C, 0x0D0604, 0xE07A5F, radius: 8),
        .make("rust", "Rust", "Weathered steel.", "Warm", 0x1E0F0A, 0x0A0503, 0xC8553D, radius: 4),
        .make("saffron", "Saffron", "Spice-market yellow.", "Warm", 0x201707, 0x0B0803, 0xF4C430),
        .make("copper", "Copper", "Polished and warm.", "Warm", 0x1D120D, 0x0A0604, 0xD98B5F, radius: 12),

        // Neon
        .make("synthwave", "Synthwave", "1986 forever.", "Neon", 0x1A0B2E, 0x07030F, 0xFF3CAC, radius: 18, focus: .glow),
        .make("cyberpunk", "Cyberpunk", "Rain, chrome, yellow.", "Neon", 0x0A0A12, 0x030306, 0xFCEE0A, radius: 0, focus: .glow),
        .make("vapor", "Vapor", "Pastel haze.", "Neon", 0x1B1033, 0x0A0614, 0x7EF9FF, radius: 20, focus: .glow),
        .make("laser", "Laser", "Green beam in the dark.", "Neon", 0x050F08, 0x010402, 0x39FF14, radius: 4, focus: .glow),
        .make("arcade", "Arcade", "Insert coin.", "Neon", 0x10061F, 0x05020B, 0xFF6B1A, radius: 2, focus: .glow),
        .make("tokyo", "Tokyo", "Shinjuku at 2 a.m.", "Neon", 0x0D0A1F, 0x04030B, 0xFF2E63, radius: 14, focus: .glow),

        // Cinema
        .make("noir", "Noir", "Hard shadows, no colour.", "Cinema", 0x121212, 0x030303, 0xD9D9D9, radius: 0),
        .make("technicolor", "Technicolor", "Saturated, golden-age.", "Cinema", 0x1A0E24, 0x08040C, 0xFF4F4F, radius: 10),
        .make("sepia", "Sepia", "Old prints, warm grain.", "Cinema", 0x231B12, 0x0D0A06, 0xD8B07A, radius: 6),
        .make("drivein", "Drive-In", "Neon sign, summer night.", "Cinema", 0x0E1324, 0x04060D, 0xFF9F1C, radius: 12),
        .make("matinee", "Matinee", "Red seats, gold trim.", "Cinema", 0x200A0E, 0x0C0305, 0xE8C15A, radius: 8),
        .make("velvet", "Velvet", "Curtain red.", "Cinema", 0x2A0710, 0x0F0205, 0xFF5A6E, radius: 16, focus: .glow),

        // Space
        .make("nebula", "Nebula", "Gas clouds in violet.", "Space", 0x150B2B, 0x05030F, 0xB388FF, radius: 18, focus: .glow),
        .make("cosmos", "Cosmos", "Deep field.", "Space", 0x070B1C, 0x010208, 0x82B1FF),
        .make("orbit", "Orbit", "Low earth, blue limb.", "Space", 0x08142A, 0x02050D, 0x4FC3F7),
        .make("pulsar", "Pulsar", "A steady white flash.", "Space", 0x0C0C18, 0x030307, 0xE3F2FD, radius: 20, focus: .glow),
        .make("comet", "Comet", "Ice and a green tail.", "Space", 0x0A1420, 0x02060A, 0x64FFDA),
        .make("mars", "Mars", "Dust and iron.", "Space", 0x220C06, 0x0B0402, 0xFF6E40, radius: 10),

        // Jewel
        .make("emerald", "Emerald", "Cut green.", "Jewel", 0x04201A, 0x010B08, 0x2ECC71, radius: 16),
        .make("sapphire", "Sapphire", "Royal blue.", "Jewel", 0x081633, 0x020713, 0x3D7DFF, radius: 16),
        .make("ruby", "Ruby", "Deep red fire.", "Jewel", 0x2A0610, 0x0E0205, 0xFF2D55, radius: 16, focus: .glow),
        .make("amethyst", "Amethyst", "Purple quartz.", "Jewel", 0x1C0B2E, 0x090311, 0xC17CFF, radius: 16),
        .make("topaz", "Topaz", "Golden blue.", "Jewel", 0x0B1B2E, 0x030912, 0xFFC857, radius: 16),
        .make("jade", "Jade", "Pale stone green.", "Jewel", 0x0E2420, 0x040C0B, 0x7FD1AE, radius: 16),

        // Light — for bright rooms
        .make("linen", "Linen", "Warm white, ink accents.", "Light", 0xF5F1EA, 0xE6E0D6, 0x2B4C7E, light: true, radius: 8),
        .make("mint", "Mint", "Cool and fresh.", "Light", 0xEEF8F3, 0xD9EDE3, 0x0F9D6E, light: true, radius: 14),
        .make("blush", "Blush", "Soft pink paper.", "Light", 0xFBF0F2, 0xF0DDE1, 0xD6336C, light: true, radius: 18),
        .make("sky", "Sky", "Clear morning.", "Light", 0xEEF5FC, 0xDCE8F5, 0x1E6FD9, light: true, radius: 14),
        .make("sand", "Sand", "Beach afternoon.", "Light", 0xF6EFE2, 0xE8DCC6, 0xC2611F, light: true, radius: 10),
        .make("lavender", "Lavender", "Quiet violet.", "Light", 0xF3F0FA, 0xE3DCF2, 0x6E4BD8, light: true, radius: 16),
    ]

    static func make(_ id: String, _ name: String, _ tagline: String, _ family: String,
                     _ top: UInt32, _ bottom: UInt32, _ accent: UInt32,
                     light: Bool = false, radius: CGFloat = 14, focus: FocusStyle = .lift) -> Theme {
        let t = RGB(top), a = RGB(accent)
        let surface = light ? t.mix(RGB(0x000000), 0.09) : t.mix(RGB(0xFFFFFF), 0.08).mix(a, 0.06)
        return Theme(
            id: id, name: name, tagline: tagline, isPremium: true, colorScheme: light ? .light : .dark,
            backgroundTop: t.color, backgroundBottom: RGB(bottom).color, surface: surface.color, accent: a.color,
            primaryText: light ? Color(white: 0.08) : .white, secondaryText: light ? Color(white: 0.36) : Color(white: 0.68),
            progress: a.color, cardCornerRadius: radius, focusStyle: focus, family: family
        )
    }
}

/// Plain sRGB components, for deriving colours at definition time.
private struct RGB {
    let r, g, b: Double
    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }
    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    func mix(_ o: RGB, _ t: Double) -> RGB { RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }
    var color: Color { Color(red: r, green: g, blue: b) }
}
