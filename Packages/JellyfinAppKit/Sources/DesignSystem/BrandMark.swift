#if os(tvOS)
public import SwiftUI

/// Bumper's mark with its ink boil: four pre-drawn frames (in the app's
/// asset catalog, from scripts/import-brand.sh) stepped at the brand's frame
/// rate. Images only, no filters, so it costs nothing on an A10X. Still
/// under Reduce Motion. For onboarding and brand moments only, never over
/// playback.
public struct BrandMark: View {
    public enum Kind: String, Sendable {
        /// BUMPER (about 4.9 : 1).
        case wordmark
        /// The sticker (square).
        case symbol
    }

    let kind: Kind
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ kind: Kind = .wordmark, height: CGFloat) {
        self.kind = kind
        self.height = height
    }

    public var body: some View {
        Group {
            if reduceMotion {
                frame(0)
            } else {
                TimelineView(.periodic(from: .now, by: 1 / BumperBrand.Boil.framesPerSecond)) { context in
                    let step = Int(context.date.timeIntervalSinceReferenceDate * BumperBrand.Boil.framesPerSecond)
                    frame(step % BumperBrand.Boil.frames)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Bumper")
        .accessibilityAddTraits(.isImage)
    }

    private func frame(_ i: Int) -> some View {
        Image("BumperBoil-\(kind.rawValue)-\(i)")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }
}
#endif
