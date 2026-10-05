#if os(tvOS)
public import SwiftUI

/// A Top Shelf link tile (Movies, TV Shows, Tonight…), until the brand kit's
/// own artwork arrives (asset `ShelfTile-<kind>`, which wins when present):
/// soot ground, the symbol and the word printed in paper slightly off-register
/// over the red plate, like the wordmark. Poster-shaped, 404 × 608 pt.
public struct ShelfTileArt: View {
    let title: String
    let symbol: String

    public init(title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    public static let size = CGSize(width: 404, height: 608)

    public var body: some View {
        ZStack {
            BumperBrand.Palette.soot
            // A faint plate band behind the word, for some warmth at a glance.
            BumperBrand.Palette.plate.opacity(0.12)
                .frame(height: 230)
                .frame(maxHeight: .infinity, alignment: .bottom)
            VStack(spacing: 46) {
                printed { Image(systemName: symbol).font(.system(size: 132, weight: .semibold)) }
                printed {
                    Text(title.uppercased())
                        .font(.system(size: 52, weight: .black, design: .serif))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 26)
                }
            }
            .offset(y: 30)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// Paper over the red plate, the plate nudged down and right.
    private func printed<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        let shape = content()
        return ZStack {
            shape.foregroundStyle(BumperBrand.Palette.plate).offset(x: 5, y: 4)
            shape.foregroundStyle(BumperBrand.Palette.paper)
        }
    }
}
#endif
