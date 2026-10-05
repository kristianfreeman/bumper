public import AppCore
public import SwiftUI

/// One text subtitle line in the user's chosen style. Shared by the player
/// and the Settings preview, so what you pick is exactly what you get.
///
/// Rendered with `drawingGroup()`: the shadows/outline are rasterised once
/// per line change and then composited as a plain texture — not re-run as
/// offscreen passes on every video frame (which the A10X can't spare).
public struct SubtitleText: View {
    let text: String
    let style: SubtitleStyle
    let scale: Double
    let font: SubtitleFont

    public init(_ text: String, style: SubtitleStyle, scale: Double, font: SubtitleFont = .system) {
        self.text = text
        self.style = style
        self.scale = scale
        self.font = font
    }

    private func face(_ weight: Font.Weight) -> Font {
        guard let family = font.family else { return .system(size: size, weight: weight) }
        return .custom(family, size: size).weight(weight)
    }

    private var size: CGFloat { 46 * scale }

    public var body: some View {
        styled
            .multilineTextAlignment(.center)
            .padding(.horizontal, style == .boxed ? 20 : 24)
            .padding(.vertical, style == .boxed ? 10 : 8)
            .background {
                if style == .boxed { RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.72)) }
            }
            .drawingGroup()
    }

    @ViewBuilder
    private var styled: some View {
        switch style {
        case .classic:
            Text(text).font(face(.semibold)).foregroundStyle(.white)
                .shadow(color: .black, radius: 3)
                .shadow(color: .black.opacity(0.8), radius: 8)
        case .outline:
            outlined(Text(text).font(face(.semibold)), fill: .white)
        case .boxed:
            Text(text).font(face(.medium)).foregroundStyle(.white)
        case .yellow:
            outlined(Text(text).font(face(.semibold)), fill: Color(red: 1, green: 0.88, blue: 0.2))
        case .light:
            Text(text).font(face(.regular)).foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.6), radius: 2)
        }
    }

    /// A crisp edge from eight hard (radius 0) shadows around the glyphs.
    private func outlined(_ text: Text, fill: Color) -> some View {
        let w = max(1.5, size / 22)
        let offsets: [(CGFloat, CGFloat)] = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
        return ZStack {
            ForEach(offsets.indices, id: \.self) { i in
                text.foregroundStyle(.black).offset(x: offsets[i].0 * w, y: offsets[i].1 * w)
            }
            text.foregroundStyle(fill)
        }
    }
}
