import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import SwiftUI

/// One search for everything: titles that match what you typed, and — when
/// it describes something ("funny 80s films I haven't seen") — the library
/// filtered to it, above them, with a way into the full collection.
struct SearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var results: [BaseItem] = []
    @State private var searching = false
    @State private var understood: Understood?
    @Environment(\.pageWidth) private var width

    struct Understood: Equatable {
        let words: String
        let filter: CollectionFilter
        let items: [BaseItem]
        let fromService: Bool
    }

    private var grouped: [(String, [BaseItem], Shelf<AnyView>.Style)] {
        [
            ("Movies", results.filter { $0.kind == .movie }, .poster),
            ("Shows", results.filter { $0.kind == .series }, .poster),
            ("Episodes", results.filter { $0.kind == .episode }, .landscape),
            ("Collections", results.filter { $0.kind == .boxSet }, .poster),
        ].filter { !$0.1.isEmpty }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Layout.shelfSpacing) {
                if let understood, understood.words == term {
                    UnderstoodSection(understood: understood, available: width)
                }
                ForEach(grouped, id: \.0) { title, items, style in
                    Shelf(title, items: items, style: style) { item in
                        AnyView(card(item, style: style))
                    }
                }
                if !query.isEmpty && results.isEmpty && understood == nil {
                    Group {
                        if searching {
                            ProgressView().controlSize(.large)
                                .accessibilityIdentifier("search.loading")
                        } else {
                            ContentUnavailableView.search(text: query)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)          // centred under the keyboard
                }
            }
            .padding(.vertical, 40)
        }
        .tvScrollClipDisabled()
        .onAppear {
            // Tests: `-searchQuery <words>` types for you.
            let args = ProcessInfo.processInfo.arguments
            if query.isEmpty, let i = args.firstIndex(of: "-searchQuery"), i + 1 < args.count { query = args[i + 1] }
        }
        .searchable(text: $query, prompt: "Titles, or what you're in the mood for")
        .task(id: query) {
            // Debounce keystrokes; the task is cancelled by the next one.
            let term = term
            guard term.count >= 2, let client = app.session?.client else { results = []; understood = nil; return }
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            if let page = try? await client.search(term), !Task.isCancelled { results = page.items }
            // Reading the words waits for a pause in typing (each new set of words is a lookup).
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await understand(term, client: client)
        }
    }

    private var term: String { query.trimmingCharacters(in: .whitespaces) }

    private func understand(_ term: String, client: JellyfinClient) async {
        let everything = CollectionFilter(base: ItemQuery(includeItemTypes: [.movie, .series]), libraryName: "Everything")
        guard case .filter(let filter, _, let fromService) = await app.search.understand(term, in: everything), !Task.isCancelled else {
            understood = nil
            return
        }
        var q = filter.query
        q.limit = 40
        let items = ((try? await client.items(q).items) ?? []).filter { filter.matches($0) }
        guard !Task.isCancelled else { return }
        TraceFile.write("search", "“\(term)” → \(filter.sentence) (\(items.count))")
        understood = Understood(words: term, filter: filter, items: Array(items.prefix(8)), fromService: fromService)
    }

    @ViewBuilder
    private func card(_ item: BaseItem, style: Shelf<AnyView>.Style) -> some View {
        if style == .landscape {
            LandscapeCard(item, kind: .still) { app.select(item, navigate: navigate) }
                .contextMenu { ItemContextMenu(item: item) }
        } else {
            PosterCard(item) { app.select(item, navigate: navigate) }
                .contextMenu { ItemContextMenu(item: item) }
        }
    }
}

/// "Movies · unwatched · comedy · from the 1980s" — eight of them, and the rest.
private struct UnderstoodSection: View {
    let understood: SearchView.Understood
    let available: CGFloat
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @Environment(\.theme) private var theme

    private var columns: Int { Layout.columns(available, minWidth: Layout.landscapeMin, max: 4) }
    private var width: CGFloat { Layout.cardWidth(available, columns: columns) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(understood.filter.parts.map(understood.filter.text).joined(separator: " · ").capitalizedFirst)
                        .font(.sectionTitle).foregroundStyle(theme.primaryText)
                    Text(understood.items.isEmpty ? "Nothing in your library fits that yet." : "From your \(understood.filter.libraryName == "Everything" ? "library" : understood.filter.libraryName.lowercased()).")
                        .font(.callout).foregroundStyle(theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("search.understood")
                .accessibilityValue(understood.fromService ? "service" : "device")
                Spacer()
                if !understood.items.isEmpty {
                    Pill("View All", systemImage: "square.grid.2x2", size: .small) {
                        navigate(.grid(GridSpec(title: understood.words.capitalizedFirst, filter: understood.filter)))
                    }
                    .accessibilityIdentifier("search.viewAll")
                }
            }
            if !understood.items.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: Layout.cardSpacing, alignment: .top), count: columns),
                          alignment: .leading, spacing: Layout.shelfSpacing + 8) {
                    ForEach(understood.items) { item in
                        LandscapeCard(item, width: width) { app.select(item, navigate: navigate) }
                            .contextMenu { ItemContextMenu(item: item) }
                            .accessibilityIdentifier("card.understood.\(item.id)")
                    }
                }
            }
        }
        .padding(.horizontal, Layout.horizontalMargin)
        .tvFocusSection()
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
