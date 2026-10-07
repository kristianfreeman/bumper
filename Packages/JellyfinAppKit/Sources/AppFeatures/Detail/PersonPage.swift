import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import Observation
import SwiftUI

/// A person's page, loaded all at once: who they are, what they're known
/// for, and their films and shows in the library.
@MainActor
@Observable
final class PersonModel {
    private(set) var details: BaseItem?
    private(set) var items: [BaseItem] = []
    /// Titles per role ("Actor": 12), as the server counts them.
    private(set) var counts: [String: Int] = [:]
    private(set) var loaded = false

    func load(personId: String, client: JellyfinClient) async {
        async let details = try? client.item(id: personId, fields: ItemField.person)
        async let items = try? client.items(.filmography(personId: personId))
        async let counts = Self.counts(personId: personId, client: client)
        self.items = PersonWords.filmography(await items?.items ?? [])
        loaded = true
        self.details = await details
        self.counts = await counts
        TraceFile.write("person", "\(personId): \(self.items.count) titles, \(self.counts)")
    }

    /// One count per role, nothing fetched but the number.
    nonisolated private static func counts(personId: String, client: JellyfinClient) async -> [String: Int] {
        await withTaskGroup(of: (String, Int?).self) { group in
            for role in PersonWords.roles {
                group.addTask {
                    var q = ItemQuery.filmography(personId: personId, roles: role.types)
                    q.limit = 0
                    q.fields = []
                    q.imageTypes = []
                    return (role.word, try? await client.items(q).totalRecordCount)
                }
            }
            var out: [String: Int] = [:]
            for await (word, n) in group { if let n { out[word] = n } }
            return out
        }
    }
}

/// Opened from a cast or crew card: their photo, name and what they're
/// known for, a few lines about them, and what of theirs is here — a
/// collection like any other, newest first.
struct PersonPage: View {
    let person: Person
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @Environment(\.theme) private var theme
    @Environment(\.pageWidth) private var width
    @State private var model = PersonModel()

    private static var phone: Bool { Layout.device == .phone }
    /// Round, like the card that opened it.
    private static let photo: CGFloat = switch Layout.device { case .tv: 240; case .mac: 150; case .pad: 160; case .phone: 104 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                header
                let columns = Layout.columns(width, minWidth: Layout.landscapeMin, max: 4)
                let cardWidth = Layout.cardWidth(width, columns: columns)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: Layout.cardSpacing, alignment: .top), count: columns),
                          alignment: .leading, spacing: Layout.shelfSpacing + 8) {
                    ForEach(model.items) { item in
                        LandscapeCard(item, width: cardWidth) { app.select(item, navigate: navigate) }
                            .contextMenu { ItemContextMenu(item: item) }
                            .accessibilityIdentifier("person.item.\(item.id)")
                    }
                }
                .tvFocusSection()
                if model.loaded, model.items.isEmpty {
                    Text("Nothing of theirs in your library.")
                        .font(.detailText).foregroundStyle(theme.secondaryText)
                        .accessibilityIdentifier("person.empty")
                }
            }
            .padding(.horizontal, Layout.horizontalMargin)
            .padding(.vertical, 50)
        }
        .tvScrollClipDisabled()
        .notesScrollActivity()
        .background(theme.backgroundGradient.ignoresSafeArea())
        .hidesNavigationBar()
        .task(id: person.id) {
            guard let client = app.session?.client else { return }
            await model.load(personId: person.id, client: client)
        }
    }

    private var name: String { model.details?.name ?? person.name ?? "" }

    private var header: some View {
        VStack(alignment: .leading, spacing: Self.phone ? 16 : 24) {
            HStack(alignment: .center, spacing: Self.phone ? 18 : 40) {
                portrait
                VStack(alignment: .leading, spacing: Self.phone ? 4 : 10) {
                    Text(name)
                        .font(.system(size: Layout.pageTitleSmall, weight: .bold)).foregroundStyle(theme.primaryText)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .accessibilityIdentifier("person.name")
                    // The card's own role stands in until the counts arrive.
                    if let knownFor = PersonWords.knownFor(counts: model.counts, fallback: person.type) {
                        Text(knownFor).font(.pageLede).foregroundStyle(theme.secondaryText)
                            .accessibilityIdentifier("person.knownFor")
                    }
                    if let life = PersonWords.life(born: model.details?.premiereDate, died: model.details?.endDate, place: model.details?.productionLocations?.first) {
                        Text(life).font(.detailText).foregroundStyle(theme.secondaryText)
                    }
                }
            }
            if let bio = model.details?.overview, !bio.isEmpty {
                Text(bio)
                    .font(.detailText).foregroundStyle(theme.secondaryText)
                    .lineLimit(Self.phone ? 6 : 4)
                    .frame(maxWidth: 1100, alignment: .leading)
                    .accessibilityIdentifier("person.bio")
            }
            if let lede = PersonWords.lede(items: model.items) {
                Text(lede).font(.sectionSubtitle).foregroundStyle(theme.secondaryText)
                    .accessibilityIdentifier("person.lede")
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.details?.id)
    }

    /// Their photo, else their initials.
    @ViewBuilder private var portrait: some View {
        let tag = model.details?.imageTags?["Primary"] ?? person.primaryImageTag
        if let tag {
            Artwork(item: Self.stub(person.id, name: name, tag: tag), kind: .poster, width: Self.photo)
                .frame(width: Self.photo, height: Self.photo)
                .clipShape(.circle)
                .accessibilityHidden(true)
        } else {
            Monogram(name, size: Self.photo)
        }
    }

    /// Enough of an item for its artwork.
    private static func stub(_ id: String, name: String, tag: String) -> BaseItem {
        var item = BaseItem(id: id, name: name, kind: .person)
        item.imageTags = ["Primary": tag]
        return item
    }
}
