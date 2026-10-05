import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import SwiftUI

/// The editorial page shared by Home and the libraries: a written header,
/// then collections — each a title, a line of copy and a grid preview
/// (four across), ending in a "View all" tile that opens the whole thing.
struct CollectionList<Header: View>: View {
    let sections: [BrowseSection]
    /// When set, the first card of the first collection binds to it (launch focus).
    var firstCardFocus: FocusState<Bool>.Binding? = nil
    /// A collection is about to scroll into view: load it if it loads lazily.
    var onNear: ((String) -> Void)? = nil
    /// Home: The queue leads the page.
    var showsQueue = false
    @ViewBuilder var header: () -> Header
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    /// The page's usable width (inside the safe area and margins): cards are sized from it.
    @Environment(\.pageWidth) private var width

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 70) {
                    // The profile corner is pinned above the page (RootView),
                    // beside the header; a phone's header starts below it.
                    header()
                        .padding(.top, Layout.device == .phone ? PillSize.regular.diameter + 8 : 0)
                        .padding(.horizontal, Layout.horizontalMargin)
                    // Not lazy: a lazy stack estimates the height of collections it
                    // hasn't built, and corrects it as they appear — the page jumped.
                    // The focus engine does the scrolling: the page used to snap
                    // each collection into place after it, which read as a jump.
                    VStack(alignment: .leading, spacing: 80) {
                        // Launch focus goes to the first card on the page: Queue's when it leads.
                        let queueLeads = showsQueue && !app.queue.isEmpty
                        if queueLeads {
                            QueueSection(store: app.queue, available: width, firstCardFocus: firstCardFocus)
                                .id("queue")
                        }
                        ForEach(sections) { section in
                            CollectionSection(section: section, available: width, firstCardFocus: !queueLeads && section.id == sections.first?.id ? firstCardFocus : nil)
                                .id(section.id)
                                .onAppear {
                                    if section.items.isEmpty { onNear?(section.id) }
                                    prepare(after: section)
                                }
                        }
                    }
                }
                .padding(.top, 40)
                .padding(.bottom, 120)
            }
            .tvScrollClipDisabled()
            .task(id: sections.count) {
                guard app.options.benchmark, sections.count > 1 else { return }
                await Benchmark.scroll(through: sections.map(\.id)) { id in
                    withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(id, anchor: .top) }
                }
            }
        }
    }

    /// Lazily loaded collections a little further down start loading now.
    private func prepare(after section: BrowseSection) {
        guard let i = sections.firstIndex(where: { $0.id == section.id }) else { return }
        for next in sections.dropFirst(i + 1).prefix(2) where next.items.isEmpty { onNear?(next.id) }
    }
}

/// One collection: "Pick up where you left off / Two things in progress —
/// about an hour in all." over a 4-across grid of up to two rows.
struct CollectionSection: View {
    let section: BrowseSection
    /// Width for the grid (the page's, inside its margins).
    var available: CGFloat = 1600
    var firstCardFocus: FocusState<Bool>.Binding? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @Environment(\.theme) private var theme

    static let rows = 2

    /// Four across on the TV (six posters), fewer where the screen's narrower.
    private var columns: Int {
        section.style == .poster ? Layout.columns(available, minWidth: Layout.posterMin, max: 6)
                                 : Layout.columns(available, minWidth: Layout.landscapeMin, max: 4)
    }
    private var width: CGFloat { Layout.cardWidth(available, columns: columns) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(section.title).font(.title3.weight(.bold)).foregroundStyle(theme.primaryText)
                if let subtitle = section.subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(theme.secondaryText).lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("collection.\(section.id)")
            if section.items.isEmpty {
                // Loading: skeleton cards at the real size, so nothing moves when they fill in.
                Grid(horizontalSpacing: Layout.cardSpacing, verticalSpacing: Layout.shelfSpacing + 8) {
                    ForEach(0..<Self.rows, id: \.self) { _ in
                        GridRow { ForEach(0..<columns, id: \.self) { _ in SkeletonCard(width: width, aspect: aspect) } }
                    }
                }
            } else {
                let shown = Array(section.items.prefix(columns * Self.rows - (section.seeAll == nil ? 0 : 1)))
                let tiles = shown.count + (section.seeAll == nil ? 0 : 1)
                // A plain grid (two rows at most): laid out exactly, nothing estimated.
                Grid(alignment: .topLeading, horizontalSpacing: Layout.cardSpacing, verticalSpacing: Layout.shelfSpacing + 8) {
                    ForEach(0..<((tiles + columns - 1) / columns), id: \.self) { row in
                        GridRow(alignment: .top) {
                            ForEach(row * columns..<min(tiles, (row + 1) * columns), id: \.self) { i in
                                if i < shown.count {
                                    let item = shown[i]
                                    card(item)
                                        .accessibilityIdentifier("card.\(section.id).\(item.id)")
                                        .reportsFocus(item, row: section.id)
                                        .modifier(FirstFocus(binding: i == 0 ? firstCardFocus : nil))
                                } else if let query = section.seeAll {
                                    ViewAllTile(count: section.total, width: width, aspect: aspect) {
                                        navigate(.grid(GridSpec(title: section.title, query: query, library: section.library ?? section.title)))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Layout.horizontalMargin)
        .tvFocusSection()
    }

    private var aspect: CGFloat {
        switch section.style {
        case .landscape: 9.0 / 16.0
        case .poster: 1.5
        case .square: 1
        }
    }

    @ViewBuilder
    private func card(_ item: BaseItem) -> some View {
        switch section.style {
        case .landscape:
            LandscapeCard(item, width: width) { app.select(item, navigate: navigate) }
            .contextMenu { ItemContextMenu(item: item) }
        case .poster:
            PosterCard(item, width: width) { app.select(item, navigate: navigate) }
                .contextMenu { ItemContextMenu(item: item) }
        case .square:
            SquareCard(item, subtitle: item.albumArtist, progress: item.progress, width: width) { navigate(.audiobook(item.id)) }
        }
    }
}

/// A card's shape while its collection loads (same size as the real thing).
struct SkeletonCard: View {
    let width: CGFloat
    let aspect: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 22).fill(theme.surface.opacity(0.5)).frame(width: width, height: width * aspect)
            VStack(alignment: .leading, spacing: 2) {
                Text(" ").font(.caption)
                Text(" ").font(.caption2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The last tile of a collection: "View all · 124".
struct ViewAllTile: View {
    let count: Int?
    let width: CGFloat
    let aspect: CGFloat
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) { Face(count: count, width: width, aspect: aspect) }
            .buttonStyle(PillButtonStyle())
            .accessibilityLabel("View all")
            .accessibilityIdentifier("collection.viewAll")
    }

    private struct Face: View {
        let count: Int?
        let width: CGFloat
        let aspect: CGFloat
        @Environment(\.isFocused) private var focused
        @Environment(\.theme) private var theme

        var body: some View {
            VStack(spacing: 14) {
                Image(systemName: "square.grid.2x2").font(.system(size: 34, weight: .semibold))
                    .frame(width: 80, height: 80)
                    .background(focused ? Color.black.opacity(0.08) : theme.primaryText.opacity(0.12), in: .circle)
                VStack(spacing: 2) {
                    Text("View all").font(.callout.weight(.semibold))
                    if let count { Text(count.formatted()).font(.caption).opacity(0.7) }
                }
            }
            .foregroundStyle(focused ? .black : theme.primaryText)
            .frame(width: width, height: width * aspect)
            .background(focused ? Color.white : theme.surface, in: .rect(cornerRadius: 22))
            .scaleEffect(focused ? 1.06 : 1)
            .shadowWhen(focused, color: .black.opacity(0.35), radius: 20, y: 10)
            .animation(.spring(duration: 0.3, bounce: 0.2), value: focused)
        }
    }
}

/// Applies `.focused` only to the one card that should take launch focus.
struct FirstFocus: ViewModifier {
    let binding: FocusState<Bool>.Binding?
    func body(content: Content) -> some View {
        if let binding { content.focused(binding) } else { content }
    }
}
