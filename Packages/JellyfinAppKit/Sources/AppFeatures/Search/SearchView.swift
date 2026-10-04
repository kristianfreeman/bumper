#if os(tvOS)
import AppCore
import DesignSystem
import JellyfinAPI
import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var results: [BaseItem] = []
    @State private var searching = false

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
                ForEach(grouped, id: \.0) { title, items, style in
                    Shelf(title, items: items, style: style) { item in
                        AnyView(card(item, style: style))
                    }
                }
                if !query.isEmpty && results.isEmpty && !searching {
                    ContentUnavailableView.search(text: query)
                }
            }
            .padding(.vertical, 40)
        }
        .scrollClipDisabled()
        .searchable(text: $query, prompt: "Movies, shows, episodes")
        .task(id: query) {
            // Debounce keystrokes; the task is cancelled by the next one.
            let term = query.trimmingCharacters(in: .whitespaces)
            guard term.count >= 2, let client = app.session?.client else { results = []; return }
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            if let page = try? await client.search(term), !Task.isCancelled { results = page.items }
        }
    }

    @ViewBuilder
    private func card(_ item: BaseItem, style: Shelf<AnyView>.Style) -> some View {
        if style == .landscape {
            LandscapeCard(item, kind: .still) { app.play(item) }
        } else {
            PosterCard(item) { navigate(.item(item)) }
        }
    }
}
#endif
