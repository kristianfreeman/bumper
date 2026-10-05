#if os(tvOS)
public import SwiftUI

/// A person without a picture: their initials in a serif, on a warm colour
/// picked from their name (the same name always gets the same colour). No
/// cyan — that's for focus and what's playing.
public struct Monogram: View {
    let name: String
    let size: CGFloat

    public init(_ name: String, size: CGFloat) {
        self.name = name
        self.size = size
    }

    /// Muted, warm, legible under paper-coloured letters.
    static let grounds: [(Color, Color)] = [
        (Color(red: 0.71, green: 0.40, blue: 0.29), Color(red: 0.52, green: 0.26, blue: 0.19)),   // clay
        (Color(red: 0.72, green: 0.56, blue: 0.25), Color(red: 0.52, green: 0.38, blue: 0.14)),   // ochre
        (Color(red: 0.42, green: 0.55, blue: 0.40), Color(red: 0.26, green: 0.38, blue: 0.27)),   // sage
        (Color(red: 0.36, green: 0.47, blue: 0.58), Color(red: 0.21, green: 0.30, blue: 0.40)),   // slate
        (Color(red: 0.53, green: 0.40, blue: 0.55), Color(red: 0.35, green: 0.25, blue: 0.38)),   // plum
        (Color(red: 0.70, green: 0.42, blue: 0.44), Color(red: 0.50, green: 0.27, blue: 0.30)),   // rose
        (Color(red: 0.33, green: 0.50, blue: 0.48), Color(red: 0.19, green: 0.33, blue: 0.32)),   // spruce
        (Color(red: 0.60, green: 0.52, blue: 0.42), Color(red: 0.42, green: 0.35, blue: 0.27)),   // sand
    ]

    static func ground(for name: String) -> (Color, Color) {
        // A stable hash (String.hashValue changes every launch).
        let h = name.lowercased().unicodeScalars.reduce(UInt32(2166136261)) { ($0 ^ $1.value) &* 16777619 }
        return grounds[Int(h % UInt32(grounds.count))]
    }

    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" || $0 == "-" })
        let letters = words.count >= 2 ? words.prefix(2).compactMap(\.first) : Array(name.prefix(1))
        return String(letters).uppercased()
    }

    public var body: some View {
        let (top, bottom) = Self.ground(for: name)
        ZStack {
            LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(Self.initials(name))
                .font(.system(size: size * (Self.initials(name).count > 1 ? 0.38 : 0.46), weight: .bold, design: .serif))
                .foregroundStyle(Color(red: 0.92, green: 0.89, blue: 0.82))           // paper
                .shadow(color: .black.opacity(0.18), radius: size * 0.02, y: size * 0.015)
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: max(1, size * 0.012)))
        .accessibilityHidden(true)
    }
}
#endif
