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
                    // Beside the TV's profile corner (pinned over the page);
                    // elsewhere below the navigation bar, which holds it.
                    header()
                        .padding(.horizontal, Layout.horizontalMargin)
                    // Not lazy on the TV: a lazy stack estimates the height of
                    // collections it hasn't built, and corrects it as they appear —
                    // focus scrolling made the page jump. Lazy elsewhere: a window
                    // resize re-laid out every card on the page each frame (the
                    // Mac's sidebar animation dropped frames), now only those on
                    // screen. The focus engine does the TV's scrolling.
                    PageStack(spacing: 80) {
                        // Launch focus goes to the first card on the page: Queue's when it leads.
                        let queueLeads = showsQueue && !app.queue.isEmpty
                        if queueLeads {
                            QueueSection(store: app.queue, available: width, firstCardFocus: firstCardFocus)
                                .id("queue")
                        }
                        // Before anything has loaded: rows of skeleton cards, so the
                        // page has its shape from the first frame (it used to be the
                        // title alone, centred, then everything jumped into place).
                        if sections.isEmpty && !queueLeads {
                            ForEach(0..<2, id: \.self) { i in
                                CollectionSection(section: BrowseSection(id: "placeholder-\(i)", title: " ", items: [], style: .landscape), available: width)
                                    .accessibilityHidden(true)
                            }
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
                .frame(maxWidth: .infinity, alignment: .leading)          // the page's width, loaded or not
                .padding(.top, Platform.isTV ? 40 : 8)
                .padding(.bottom, 120)
            }
            .tvScrollClipDisabled()
            .notesScrollActivity()
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
                Text(section.title).font(.sectionTitle).foregroundStyle(theme.primaryText)
                if let subtitle = section.subtitle {
                    Text(subtitle).font(.sectionSubtitle).foregroundStyle(theme.secondaryText).lineLimit(2)
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
                // Two rows at most; with more behind it, the last place is "View all".
                let more = section.seeAll != nil || section.arrivalsSpec != nil || section.items.count > columns * Self.rows
                let shown = Array(section.items.prefix(columns * Self.rows - (more ? 1 : 0)))
                let tiles = shown.count + (more ? 1 : 0)
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
                                } else if more {
                                    ViewAllTile(count: section.total.flatMap { $0 > 0 ? $0 : nil }, width: width, aspect: aspect) {
                                        if let spec = section.arrivalsSpec { navigate(.arrivals(spec)) }
                                        else if let lib = section.playlistsLibrary { navigate(.library(lib)) }
                                        else { navigate(.grid(section.seeAllSpec)) }
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
            if let arrival = section.arrivals?.first(where: { $0.id == item.id }) {
                ArrivalCard(arrival: arrival, width: width)
            } else if item.kind == .playlist {
                PlaylistCard(playlist: item, width: width)
            } else {
                LandscapeCard(item, width: width) { app.select(item, navigate: navigate) }
                    .contextMenu { ItemContextMenu(item: item) }
            }
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
                Text(" ").font(.labelText)
                Text(" ").font(.fineText)
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
            // Sized to the card: the TV's 80 pt circle overflowed a phone's.
            let circle = min(80, max(34, width * aspect * 0.42))
            VStack(spacing: circle * 0.16) {
                Image(systemName: "square.grid.2x2").font(.system(size: circle * 0.42, weight: .semibold))
                    .frame(width: circle, height: circle)
                    .background(focused ? Color.black.opacity(0.08) : theme.primaryText.opacity(0.12), in: .circle)
                VStack(spacing: 1) {
                    Text("View all").font((Layout.device == .phone ? Font.caption : .detailText).weight(.semibold))
                    if let count { Text(count.formatted()).font(Layout.device == .phone ? .caption2 : .labelText).opacity(0.7) }
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

/// The collections' stack: built in full on the TV, lazily elsewhere (see
/// CollectionList).
private struct PageStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        if Platform.isTV {
            VStack(alignment: .leading, spacing: spacing, content: content)
        } else {
            LazyVStack(alignment: .leading, spacing: spacing, content: content)
        }
    }
}
