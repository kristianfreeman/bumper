#if os(tvOS)
public import JellyfinAPI
public import SwiftUI

/// Focus treatment shared by every card. `.lift` uses the system highlight
/// (parallax + specular, the native tvOS feel); `.glow` (premium themes) adds
/// an accent-coloured halo.
struct CardFocusModifier: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        let base = content
            .clipShape(.rect(cornerRadius: theme.cardCornerRadius))
            .hoverEffect(.highlight)
        // Only glow themes pay for a shadow, and only on the focused card:
        // a shadow (even a clear one) can force an offscreen render pass.
        if theme.focusStyle == .glow && isFocused {
            base.shadow(color: theme.accent.opacity(0.55), radius: 24)
        } else {
            base
        }
    }
}

extension View {
    func cardFocus() -> some View { modifier(CardFocusModifier()) }
}

/// Thin playback-progress bar overlaid on artwork.
public struct ProgressStrip: View {
    let value: Double
    @Environment(\.theme) private var theme

    public init(_ value: Double) { self.value = value }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.45))
                Capsule().fill(theme.progress).frame(width: max(6, geo.size.width * value))
            }
        }
        .frame(height: 6)
    }
}

/// 2:3 poster card — movies, series, collections.
public struct PosterCard: View {
    let item: BaseItem
    let width: CGFloat
    let action: () -> Void
    @Environment(\.theme) private var theme

    public init(_ item: BaseItem, width: CGFloat = Layout.posterWidth, action: @escaping () -> Void) {
        self.item = item
        self.width = width
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Artwork(item: item, kind: .poster, width: width)
                    .frame(width: width, height: width * 1.5)
                    .overlay(alignment: .topTrailing) { WatchedBadge(item: item).padding(10) }
                    .overlay(alignment: .bottom) {
                        if let p = item.progress, !item.isPlayed { ProgressStrip(p).padding(12) }
                    }
                    .cardFocus()
                Text(item.name ?? "")
                    .font(.caption)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(item.name ?? "Untitled")
    }
}

/// 1:1 card — audiobook covers: title, author, progress.
public struct SquareCard: View {
    let item: BaseItem
    let subtitle: String?
    let progress: Double?
    let width: CGFloat
    let action: () -> Void
    @Environment(\.theme) private var theme

    public init(_ item: BaseItem, subtitle: String?, progress: Double?, width: CGFloat = Layout.squareWidth, action: @escaping () -> Void) {
        self.item = item
        self.subtitle = subtitle
        self.progress = progress
        self.width = width
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Artwork(item: item, kind: .poster, width: width)
                    .frame(width: width, height: width)
                    .overlay(alignment: .bottom) {
                        if let progress { ProgressStrip(progress).padding(12) }
                    }
                    .cardFocus()
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name ?? "").font(.caption).foregroundStyle(theme.primaryText)
                    Text(subtitle ?? " ").font(.caption2).foregroundStyle(theme.secondaryText)
                }
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(item.name ?? "Untitled")
    }
}

/// 16:9 card — continue watching, episodes, next up.
public struct LandscapeCard: View {
    let item: BaseItem
    let width: CGFloat
    let kind: ArtworkKind
    let action: () -> Void
    @Environment(\.theme) private var theme

    public init(_ item: BaseItem, width: CGFloat = Layout.landscapeWidth, kind: ArtworkKind = .landscape, action: @escaping () -> Void) {
        self.item = item
        self.width = width
        self.kind = kind
        self.action = action
    }

    private var title: String {
        item.kind == .episode ? (item.seriesName ?? item.name ?? "") : (item.name ?? "")
    }

    private var subtitle: String? {
        if item.kind == .episode {
            return [item.episodeLabel, item.name].compactMap { $0 }.joined(separator: " · ")
        }
        return item.productionYear.map(String.init)
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Artwork(item: item, kind: kind, width: width)
                    .frame(width: width, height: width * 9 / 16)
                    .overlay(alignment: .bottom) {
                        if let p = item.progress, !item.isPlayed {
                            ProgressStrip(p).padding(.horizontal, 14).padding(.bottom, 12)
                        }
                    }
                    .overlay(alignment: .topTrailing) { WatchedBadge(item: item).padding(10) }
                    .cardFocus()
                // Always two lines (an empty one if there's no subtitle): every
                // card is the same height, so grids never re-measure as they scroll.
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(theme.primaryText).lineLimit(1)
                    Text(subtitle ?? " ").font(.caption2).foregroundStyle(theme.secondaryText).lineLimit(1)
                }
                .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel([title, subtitle].compactMap { $0 }.joined(separator: ", "))
    }
}

/// Round headshot for cast & crew.
public struct PersonCard: View {
    let person: Person
    let action: () -> Void
    @Environment(\.theme) private var theme

    public init(_ person: Person, action: @escaping () -> Void) {
        self.person = person
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Artwork(person.primaryImageTag.map { ArtworkSource(itemId: person.id, type: .primary, tag: $0, blurHash: person.imageBlurHashes?["Primary"]?[$0]) }, kind: .poster, width: Layout.castWidth)
                    .frame(width: Layout.castWidth, height: Layout.castWidth)
                    .clipShape(.circle)
                    .hoverEffect(.highlight)
                Text(person.name ?? "").font(.caption2).foregroundStyle(theme.primaryText).lineLimit(1)
                Text(person.role ?? "").font(.caption2).foregroundStyle(theme.secondaryText).lineLimit(1)
            }
            .frame(width: Layout.castWidth + 20)
        }
        .buttonStyle(.borderless)
    }
}

struct WatchedBadge: View {
    let item: BaseItem
    @Environment(\.theme) private var theme

    var body: some View {
        if item.isPlayed {
            Image(systemName: "checkmark")
                .font(.caption2.bold())
                .foregroundStyle(.black)
                .padding(8)
                .background(theme.accent, in: .circle)
        } else if let unplayed = item.userData?.unplayedItemCount, unplayed > 0, item.kind == .series || item.kind == .season {
            Text("\(unplayed)")
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(.black)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(theme.accent, in: .capsule)
        }
    }
}

/// "4K", "DOLBY VISION", "ATMOS" style capability badges.
public struct Badge: View {
    let text: String
    @Environment(\.theme) private var theme
    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.secondaryText.opacity(0.7), lineWidth: 1.5))
    }
}
#endif
