public import AppCore
public import JellyfinAPI
public import SwiftUI

/// A row's card that opens on focus (the TV): it widens to the item's wide
/// artwork at the same height, with its name, what it is and how far you
/// are on it — the row's own hero. Unfocused, it's the usual picture with
/// its name underneath. Only its width changes: the row's height stays put,
/// so nothing above or below moves, and its neighbours just slide over.
public struct OpenTile: View {
    public enum Shape: Sendable { case poster, landscape }

    let item: BaseItem
    let shape: Shape
    let width: CGFloat
    var title: String?
    var detail: String?
    let action: () -> Void

    public init(_ item: BaseItem, shape: Shape, width: CGFloat, title: String? = nil, detail: String? = nil, action: @escaping () -> Void) {
        self.item = item
        self.shape = shape
        self.width = width
        self.title = title
        self.detail = detail
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Face(item: item, shape: shape, width: width, title: title, detail: detail)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel([title ?? Face.name(item), detail ?? Face.line(item)].compactMap { $0 }.joined(separator: ", "))
    }

    /// The card's height is its picture's; open, its width is the wide art's
    /// at that height (a poster's) or twice its own (a landscape card's).
    static func sizes(_ shape: Shape, width: CGFloat) -> (art: CGFloat, open: CGFloat) {
        switch shape {
        case .poster: let h = width * 1.5; return (h, (h * 16 / 9).rounded())
        case .landscape: return (width * 9 / 16, width * 2)
        }
    }

    private struct Face: View {
        let item: BaseItem
        let shape: Shape
        let width: CGFloat
        let title: String?
        let detail: String?
        @Environment(\.isFocused) private var focused
        @Environment(\.theme) private var theme
        @Environment(\.playedNow) private var playedNow

        static func name(_ item: BaseItem) -> String {
            item.kind == .episode ? (item.seriesName ?? item.name ?? "") : (item.name ?? "")
        }

        static func line(_ item: BaseItem) -> String? {
            if item.kind == .episode { return [item.episodeLabel, item.name].compactMap { $0 }.joined(separator: " · ") }
            let runtime = item.runtime.map { d -> String in
                let m = Int(d.components.seconds / 60)
                return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
            }
            return [item.productionYear.map(String.init), runtime].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        }

        private var open: Bool { Platform.isTV && focused }
        /// A lead row's open tile (half the screen): hero-sized words.
        private var big: Bool { OpenTile.sizes(shape, width: width).art > 400 }
        private var progress: Double? {
            guard let p = item.progress, !(playedNow[item.id] ?? item.isPlayed) else { return nil }
            return p
        }

        var body: some View {
            let size = OpenTile.sizes(shape, width: width)
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    if open {
                        // The wide art, the words on it.
                        Artwork(item: item, kind: .backdrop, width: size.open)
                            .frame(width: size.open, height: size.art)
                        LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0)], startPoint: .leading, endPoint: .center)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title ?? Self.name(item))
                                .font(big ? .system(size: 56, weight: .heavy) : .cardTitle.weight(.bold))
                                .lineLimit(2)
                            if let line = detail ?? Self.line(item) {
                                Text(line).font(.cardSubtitle).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                            }
                            if let overview = item.overview, shape == .poster || size.art > 200 {
                                Text(overview).font(.cardSubtitle).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                            }
                            if let progress { ProgressStrip(progress).frame(width: min(size.open * 0.4, 360)) }
                            if big {
                                Text(progress != nil ? "▶ Resume  ·  Start Over  ·  Details" : "▶ Play  ·  Details")
                                    .font(.cardTitle.weight(.semibold)).padding(.top, 6)
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: size.open * 0.55, alignment: .leading)
                        .padding(size.art > 260 ? 28 : 18)
                    } else {
                        Artwork(item: item, kind: shape == .poster ? .poster : .landscape, width: width)
                            .frame(width: width, height: size.art)
                            .overlay(alignment: .bottom) { if let progress { ProgressStrip(progress).padding(10) } }
                            .overlay(alignment: .topTrailing) { WatchedBadge(item: item).padding(10) }
                    }
                }
                .frame(width: open ? size.open : width, height: size.art, alignment: .leading)
                .cardFocus()
                // Under every closed card its name (the open one says it on the
                // art): two lines kept either way, so the row never changes height.
                VStack(alignment: .leading, spacing: 2) {
                    Text(open ? " " : (title ?? Self.name(item))).font(.cardTitle).foregroundStyle(theme.primaryText).lineLimit(1)
                    Text(open ? " " : (detail ?? Self.line(item) ?? " ")).font(.cardSubtitle).foregroundStyle(theme.secondaryText).lineLimit(1)
                }
                .frame(width: width, alignment: .leading)
            }
            .animation(.smooth(duration: 0.22), value: open)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
