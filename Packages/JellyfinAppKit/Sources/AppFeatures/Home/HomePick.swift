import AppCore
import DesignSystem
import JellyfinAPI
import SwiftUI

/// Home's lead: the one thing you'd most likely watch now (`HomePicks`),
/// with Play ready, and the few others in a row under it. On the TV,
/// moving along that row brings each one up and Select plays it; on touch
/// and the Mac, a tap brings it up and its Play plays it.
///
/// Wide (TV, iPad, a big Mac window): the words beside the picture. Narrow
/// (iPhone, a small window): the picture, then the words under it.
struct HomePickSection: View {
    let picks: [HomePicks.Pick]
    /// Play takes launch focus (Home's first focus) when given.
    var playFocus: FocusState<Bool>.Binding? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @Environment(\.pageWidth) private var width
    @Environment(\.theme) private var theme
    @Environment(\.focusTracker) private var tracker
    @Environment(\.jellyfin) private var client
    @Environment(\.displayScale) private var scale
    /// The pick that's up (the first until another is chosen).
    @State private var chosen: String?

    static let row = "picks"
    private var compact: Bool { width < 700 }
    private var shown: HomePicks.Pick? { picks.first { $0.id == chosen } ?? picks.first }

    var body: some View {
        if let pick = shown {
            Group {
                if compact { narrow(pick) } else { wide(pick) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.pick")
            // On the TV a pick comes up as focus reaches its card.
            .onChange(of: tracker?.featured?.id) { _, id in
                guard Platform.isTV, tracker?.row == Self.row, let id, picks.contains(where: { $0.id == id }) else { return }
                chosen = id
            }
            .onChange(of: picks.map(\.id)) { _, ids in if let chosen, !ids.contains(chosen) { self.chosen = nil } }
            // Every pick's picture and logo in memory before it's brought up:
            // moving along the row swaps drawn images, never loads them.
            .task(id: picks.map(\.id)) { prefetch() }
        }
    }

    private var artWidth: CGFloat { compact ? width : (width * 0.46).rounded() }

    private func prefetch() {
        guard let client else { return }
        let logoWidth = HeroLogo.box(for: Layout.device).width
        let requests = picks.flatMap { pick in
            [ArtworkSource.resolve(pick.item, .backdrop)?.request(client: client, pixelWidth: Int(artWidth * scale)),
             ArtworkSource.resolve(pick.item, .logo)?.request(client: client, pixelWidth: Int(logoWidth * scale))].compactMap { $0 }
        }
        ImagePipeline.shared.prefetch(requests)
    }

    // MARK: Layouts

    private func wide(_ pick: HomePicks.Pick) -> some View {
        VStack(alignment: .leading, spacing: Platform.isTV ? 44 : 28) {
            // As tall as the picture whatever the words: nothing below moves
            // as picks come up. A focus section across the whole width, so Up
            // from anywhere along the row below lands on Play.
            HStack(alignment: .center, spacing: Layout.cardSpacing * 1.5) {
                words(pick)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                picture(pick.item, width: artWidth)
            }
            .frame(height: (artWidth * 9 / 16).rounded())
            .tvFocusSection()
            if picks.count > 1 { others(cardWidth: Platform.isTV ? 300 : 220) }
        }
    }

    private func narrow(_ pick: HomePicks.Pick) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            picture(pick.item, width: artWidth)
            words(pick)
            if picks.count > 1 { others(cardWidth: 160) }
        }
    }

    // MARK: Parts

    /// Why it's here, the title (its logo when there is one), and for an
    /// episode just which one — its words are spoilers and its page is the
    /// show's; for a film what it is and what it's about. Then Resume (with
    /// what's left) and Go to.
    private func words(_ pick: HomePicks.Pick) -> some View {
        let item = pick.item
        let episode = item.kind == .episode
        return VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            if !pick.reasonIsTimeLeft {
                Text(pick.reason.uppercased())
                    .font(.labelText.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(theme.secondaryText)
            }
            if ArtworkSource.resolve(item, .logo) != nil {
                HeroLogo(item: item, box: HeroLogo.box(for: Layout.device))
            } else {
                Text(episode ? item.seriesName ?? "" : item.name ?? "")
                    .font(.system(size: Layout.pageTitle, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)
            }
            if episode {
                Text([item.episodeLabel, item.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.detailText.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
            } else {
                MetadataLine(item: item)
                if let overview = item.overview {
                    Text(overview)
                        .font(.detailText)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(compact ? 2 : 3)
                        .frame(maxWidth: 1000, alignment: .leading)
                }
            }
            HStack(spacing: Platform.isTV ? 22 : 14) {
                Pill(Self.playTitle(pick), systemImage: "play.fill", prominent: true, alwaysShowsTitle: true) {
                    app.play(item)
                }
                .modifier(FirstFocus(binding: playFocus))
                .accessibilityIdentifier("home.pick.play")
                let goTo = episode ? "Go to Episode" : "Go to Film"
                Pill(goTo, systemImage: "arrow.right") { navigate(.item(item)) }
                    .pillCaption(goTo)
                    .accessibilityIdentifier("home.pick.details")
            }
            .padding(.top, compact ? 4 : 10)
            .environment(\.pillCaptions, true)
            // Play focused: get the stream ready, so Select starts at once.
            .onChange(of: playFocus?.wrappedValue) { _, focused in if focused == true { tracker?.focused(item, row: Self.row) } }
        }
        .animation(.easeOut(duration: 0.2), value: item.id)
    }

    /// "Resume · 18m left", or "Play".
    static func playTitle(_ pick: HomePicks.Pick) -> String {
        guard let left = pick.minutesLeft else { return "Play" }
        return "Resume · \(MetadataLine.runtimeString(.seconds(max(1, left) * 60))) left"
    }

    /// The show's or film's own picture (never an episode's still: no spoilers).
    private func picture(_ item: BaseItem, width: CGFloat) -> some View {
        Artwork(item: item, kind: .backdrop, width: width)
            .frame(width: width, height: (width * 9 / 16).rounded())
            .overlay(alignment: .bottom) {
                if let p = item.progress, !(app.playedNow[item.id] ?? item.isPlayed) {
                    ProgressStrip(p).padding(.horizontal, 16).padding(.bottom, 14)
                }
            }
            .clipShape(.rect(cornerRadius: theme.cardCornerRadius))
            .accessibilityHidden(true)
    }

    /// The others, each with its reason under it.
    private func others(cardWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Platform.isTV ? 4 : 8) {
            Text("Or…").font(.sectionTitle).foregroundStyle(theme.primaryText)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Layout.cardSpacing) {
                    ForEach(picks) { pick in
                        let up = pick.id == shown?.id
                        LandscapeCard(pick.item, width: cardWidth, kind: .landscape, caption: pick.reason) {
                            // The TV: it's already up (focus brought it), so Select plays.
                            if Platform.isTV || up { app.play(pick.item) } else { withAnimation(.smooth(duration: 0.25)) { chosen = pick.id } }
                        }
                        .opacity(Platform.isTV || up ? 1 : 0.7)
                        .contextMenu { ItemContextMenu(item: pick.item) }
                        .reportsFocus(pick.item, row: Self.row)
                        .accessibilityIdentifier("card.picks.\(pick.id)")
                    }
                }
            }
            .rowInMargins()
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Layout.horizontalMargin)        // the row keeps its own margins
        }
        .tvFocusSection()
    }
}
