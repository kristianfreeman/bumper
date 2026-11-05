import AppCore
import DesignSystem
import JellyfinAPI
import SwiftUI

/// Every few rows on Home and in the libraries, one film from the row below
/// given the page's whole width: its picture, its logo, a line of what it's
/// about, and Play. Landmarks down a long page, so it isn't row after row
/// of the same.
///
/// A spotlight is a row of its own (`BrowseSection.spotlight` names the row
/// it's from). It fills when that row does: the best rated there you haven't
/// seen or started, with a picture and something said about it, and not one
/// another spotlight on the page has. When there's none, it goes.
nonisolated enum Spotlight {
    /// Where they go: after the page's first few rows, then every few.
    static let first = 3
    static let every = 5

    /// `rows` with a spotlight above the first few's next and every fifth
    /// after, each from the row below it (when that row loads by query).
    static func placed(in rows: [BrowseSection]) -> [BrowseSection] {
        var out: [BrowseSection] = []
        for (i, row) in rows.enumerated() {
            if i >= first, (i - first) % every == 0, case .query = row.source {
                var s = BrowseSection(id: "spotlight-\(row.id)", title: row.title, items: [], style: .landscape)
                s.spotlight = row.id
                out.append(s)
            }
            out.append(row)
        }
        return out
    }

    /// Who could be one, best first: films and shows you haven't seen or
    /// started (Continue Watching has those), with a picture, not already
    /// in a spotlight.
    static func candidates(_ items: [BaseItem], excluding: Set<String>) -> [BaseItem] {
        items.filter { item in
            [.movie, .series].contains(item.kind) && !item.isPlayed && item.resumePosition == nil
                && !excluding.contains(item.id) && ArtworkSource.resolve(item, .backdrop) != nil
        }
        .sorted { ($0.communityRating ?? 0, $1.name ?? "") > ($1.communityRating ?? 0, $0.name ?? "") }
    }

    /// The overview's first sentence, or two when the first is very short
    /// ("A thief."): a line of what it's about, not the whole blurb.
    static func blurb(_ overview: String) -> String {
        let text = overview.trimmingCharacters(in: .whitespacesAndNewlines)
        var end = text.startIndex
        var sentences = 0
        while let stop = text[end...].firstIndex(where: { ".!?".contains($0) }) {
            end = text.index(after: stop)
            // "Dr. Strange", "U.S.": not the end of a sentence unless a space and a capital follow.
            let rest = text[end...]
            guard rest.first == " ", rest.dropFirst().first?.isUppercase == true || rest.dropFirst().first?.isNumber == true else {
                if rest.isEmpty { break } else { continue }
            }
            sentences += 1
            if text.distance(from: text.startIndex, to: end) >= 40 || sentences == 2 { break }
        }
        return end == text.startIndex ? text : String(text[..<end])
    }
}

/// A spotlight on the page. The TV, an iPad and the Mac draw it as one wide
/// picture with the words over its left side; a phone (or a narrow window)
/// as the picture with the words beneath.
struct SpotlightSection: View, Equatable {
    let section: BrowseSection
    var available: CGFloat
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @Environment(\.theme) private var theme

    nonisolated static func == (a: Self, b: Self) -> Bool { a.section == b.section && a.available == b.available }

    private var compact: Bool { available < 700 }
    private var radius: CGFloat { Platform.isTV ? 28 : 16 }
    /// Wide: at least this tall (about a third of the TV's screen); taller
    /// only if its words need it.
    private var height: CGFloat { Platform.isTV ? 470 : min(max(available * 0.36, 280), 440) }
    /// The logo's room: smaller than Home's pick, so the words fit the card.
    private var logoBox: CGSize {
        let pick = HeroLogo.box(for: Layout.device)
        return CGSize(width: pick.width * 0.8, height: pick.height * 0.7)
    }
    private var pictureHeight: CGFloat { compact ? (available * 9 / 16).rounded() : height }

    var body: some View {
        Group {
            if let item = section.items.first {
                if compact {
                    VStack(alignment: .leading, spacing: 14) {
                        picture(item)
                        words(item)
                    }
                } else {
                    // The words make the card's size and the picture fills
                    // behind them: one box, whatever the words need. (Fixed
                    // to the picture's height, the TV's words ran over it,
                    // above and below.)
                    words(item)
                        .frame(maxWidth: available * 0.5, alignment: .leading)
                        .padding(Platform.isTV ? 48 : 28)
                        .frame(width: available, alignment: .leading)
                        .frame(minHeight: height)
                        .background {
                            ZStack {
                                Artwork(item: item, kind: .backdrop, width: available)
                                // The words' side darkened, so they read over any picture.
                                LinearGradient(stops: [.init(color: theme.backgroundBottom.opacity(0.94), location: 0),
                                                       .init(color: theme.backgroundBottom.opacity(0.7), location: 0.4),
                                                       .init(color: .clear, location: 0.75)],
                                               startPoint: .leading, endPoint: .trailing)
                            }
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: radius))
                }
            } else {
                // Its place while it fills, at its size, so nothing moves.
                RoundedRectangle(cornerRadius: radius).fill(theme.surface.opacity(0.5))
                    .frame(height: compact ? pictureHeight + 170 : height)
            }
        }
        .frame(width: available, alignment: .leading)
        .padding(.horizontal, Layout.horizontalMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spotlight.\(section.spotlight ?? section.id)")
        .tvFocusSection()
    }

    private func picture(_ item: BaseItem) -> some View {
        Artwork(item: item, kind: .backdrop, width: available)
            .frame(width: available, height: pictureHeight)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .accessibilityHidden(true)
    }

    /// Which row it's from, its logo (or name), what it is, a line of what
    /// it's about, then Play (a film) and Go to.
    private func words(_ item: BaseItem) -> some View {
        let film = item.kind == .movie
        let goTo = film ? "Go to Film" : "Go to Show"
        return VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Text("From \(section.title)".uppercased())
                .font(.labelText.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(theme.secondaryText)
            if ArtworkSource.resolve(item, .logo) != nil {
                HeroLogo(item: item, box: logoBox)
            } else {
                Text(item.name ?? "")
                    .font(.system(size: Layout.pageTitle, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)
            }
            MetadataLine(item: item)
            if let overview = item.overview, !overview.isEmpty {
                Text(Spotlight.blurb(overview))
                    .font(.detailText)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
            }
            HStack(spacing: Platform.isTV ? 22 : 14) {
                // A show has no one thing to play: its page is the way in.
                if film {
                    Pill("Play", systemImage: "play.fill", prominent: true, alwaysShowsTitle: true) { app.play(item) }
                        .reportsFocus(item, row: section.id)
                        .accessibilityIdentifier("spotlight.play")
                }
                Pill(goTo, systemImage: "arrow.right", prominent: !film, alwaysShowsTitle: !film) { navigate(.item(item)) }
                    .pillCaption(goTo)
                    .reportsFocus(item, row: section.id)
                    .accessibilityIdentifier("spotlight.details")
            }
            .padding(.top, compact ? 4 : 6)
            .environment(\.pillCaptions, true)
        }
    }
}
