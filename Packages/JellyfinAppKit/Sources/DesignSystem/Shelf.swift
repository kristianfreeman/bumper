#if os(tvOS)
import AppCore
import Instrumentation
import os
public import JellyfinAPI
public import SwiftUI

/// The app's standard browse primitive: a titled, horizontally scrolling row
/// ("Netflix style"). Every browse surface is a vertical stack of shelves;
/// the only grid is a library's exhaustive "See All" view.
///
/// Why shelves: the tvOS focus engine is built for horizontal rows — one
/// swipe moves one card, rows give context ("Continue Watching") for free,
/// and a vertical stack of lazy rows renders far fewer views than a grid of
/// the same content.
public struct Shelf<Content: View>: View {
    public enum Style: Sendable { case poster, landscape, cast, square }

    let title: String
    let items: [BaseItem]
    let style: Style
    let onSeeAll: (() -> Void)?
    let content: (BaseItem) -> Content

    @Environment(\.theme) private var theme
    @Environment(\.jellyfin) private var client
    @Environment(\.displayScale) private var scale

    public init(_ title: String, items: [BaseItem], style: Style = .poster, onSeeAll: (() -> Void)? = nil, @ViewBuilder content: @escaping (BaseItem) -> Content) {
        self.title = title
        self.items = items
        self.style = style
        self.onSeeAll = onSeeAll
        self.content = content
    }

    private var cardWidth: CGFloat {
        switch style {
        case .poster: Layout.posterWidth
        case .landscape: Layout.landscapeWidth
        case .cast: Layout.castWidth
        case .square: Layout.squareWidth
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, Layout.horizontalMargin)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Layout.cardSpacing) {
                    ForEach(items) { item in
                        content(item)
                    }
                    if let onSeeAll {
                        SeeAllCard(width: cardWidth, aspect: style == .poster ? 1.5 : style == .square ? 1 : 9.0 / 16.0, action: onSeeAll)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Layout.horizontalMargin)
                .padding(.vertical, 28)
            }
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
            .onScrollTargetVisibilityChange(idType: BaseItem.ID.self, threshold: 0.01) { visible in
                prefetch(after: visible)
            }
        }
        .focusSection()
    }

    /// Warm the next screenful of artwork while the user is still looking at
    /// this one, so cards arrive already decoded.
    private func prefetch(after visible: [BaseItem.ID]) {
        guard let client, let last = visible.last, let idx = items.firstIndex(where: { $0.id == last }) else { return }
        let upcoming = items[(idx + 1)..<min(items.count, idx + 8)]
        let kind: ArtworkKind = style == .poster || style == .square ? .poster : .landscape
        let requests = upcoming.compactMap { ArtworkSource.resolve($0, kind)?.request(client: client, pixelWidth: Int(cardWidth * scale)) }
        ImagePipeline.shared.prefetch(requests)
    }
}

struct SeeAllCard: View {
    let width: CGFloat
    let aspect: CGFloat
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.3x3.fill").font(.title2)
                Text("See All").font(.caption.weight(.semibold))
            }
            .foregroundStyle(theme.primaryText)
            .frame(width: width, height: width * aspect)
            .background(theme.surface)
            .cardFocus()
        }
        .buttonStyle(.borderless)
    }
}

/// Exhaustive library index. Same cards and metrics as shelves, so the app
/// still reads as one design system.
public struct MediaGrid: View {
    let items: [BaseItem]
    let onSelect: (BaseItem) -> Void
    let onReachEnd: () -> Void

    public init(items: [BaseItem], onSelect: @escaping (BaseItem) -> Void, onReachEnd: @escaping () -> Void) {
        self.items = items
        self.onSelect = onSelect
        self.onReachEnd = onReachEnd
    }

    private let columns = Array(repeating: GridItem(.fixed(Layout.posterWidth), spacing: Layout.cardSpacing), count: 7)

    public var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 48) {
            ForEach(items) { item in
                PosterCard(item) { onSelect(item) }
                    .onAppear {
                        // Page in well before the end so the grid never visibly "loads".
                        if items.count > 20, item.id == items[items.count - 21].id { onReachEnd() }
                    }
            }
        }
        .padding(.horizontal, Layout.horizontalMargin)
        .focusSection()
    }
}

/// Full-bleed backdrop that follows focus. The current image stays up until
/// the next one is decoded, then the new one fades in *over* it — image to
/// image, never dipping to the plain background in between.
public struct FocusBackdrop: View {
    let item: BaseItem?
    @Environment(\.theme) private var theme
    @Environment(\.jellyfin) private var client
    @Environment(\.displayScale) private var scale
    /// A stack of layers, newest on top. Each new image fades in over what's
    /// there on its own animation; the layers it covers are dropped once it's
    /// opaque. Fast focus changes just stack a few fades — no shared opacity
    /// to get stuck half-way, and no dip to the background between images.
    @State private var layers: [Shown] = []
    @State private var sequence = 0

    struct Shown: Identifiable, Equatable {
        let id: Int
        let key: String
        /// nil: no backdrop for this item (the theme background shows).
        let image: CGImage?
        static func == (a: Shown, b: Shown) -> Bool { a.id == b.id }
    }

    public init(_ item: BaseItem?) { self.item = item }

    private var request: ImageRequest? {
        guard let item, let client, let source = ArtworkSource.resolve(item, .backdrop) else { return nil }
        return source.request(client: client, pixelWidth: Int(1920 * scale))
    }


    public var body: some View {
        let request = request
        // First appearance with the image already in memory: draw it in this
        // very frame — no task hop, no fade.
        let immediate: CGImage? = layers.isEmpty ? request.flatMap { ImagePipeline.shared.cachedImage(for: $0) } : nil
        ZStack {
            theme.backgroundGradient
            ZStack {
                if let immediate { layer(immediate) }
                ForEach(layers) { shown in
                    Group {
                        if let image = shown.image { layer(image) } else { theme.backgroundGradient }
                    }
                    .zIndex(Double(shown.id))
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
                }
            }
            // Dim once, above the stack. (An .opacity on the stack applies to
            // each image separately: the outgoing one showed through the
            // incoming one and vanished at the end of the fade — a flicker.)
            theme.backgroundGradient.opacity(theme.colorScheme == .light ? 0.65 : 0.45)
            LinearGradient(colors: [theme.backgroundBottom.opacity(0.2), theme.backgroundBottom.opacity(0.85), theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [theme.backgroundBottom.opacity(0.9), .clear], startPoint: .leading, endPoint: .center)
        }
        .ignoresSafeArea()
        .task(id: request?.key ?? "none") {
            let key = request?.key ?? "none"
            guard layers.last?.key != key else { return }
            var image: CGImage?
            if let request {
                image = ImagePipeline.shared.cachedImage(for: request)
                if image == nil { image = try? await ImagePipeline.shared.image(for: request) }
                guard image != nil, !Task.isCancelled else { return }        // keep what's shown
            }
            sequence += 1
            let shown = Shown(id: sequence, key: key, image: image)
            if layers.isEmpty, immediate != nil {
                layers = [shown]                                         // already on screen
                return
            }
            // At most three layers (each is a full-screen image to composite):
            // focus changes are debounced to ≥160 ms, so the oldest of three
            // has finished its fade by the time a fourth arrives.
            if layers.count >= 3 {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { layers.removeFirst(layers.count - 2) }
            }
            withAnimation(.easeInOut(duration: 0.35)) { layers.append(shown) }
            // Once it's opaque, drop what it covers. Cancelled (focus moved
            // on): the newer image's task drops everything under it instead.
            guard (try? await Task.sleep(for: .milliseconds(400))) != nil else { return }
            if let i = layers.firstIndex(of: shown), i > 0 {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { layers.removeFirst(i) }
            }
        }
    }

    private func layer(_ image: CGImage) -> some View {
        Image(decorative: image, scale: scale)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}
#endif
