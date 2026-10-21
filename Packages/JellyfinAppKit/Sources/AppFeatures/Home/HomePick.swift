import AppCore
import DesignSystem
import JellyfinAPI
import SwiftUI

/// Home's lead, nearly a screen of its own: the one thing you'd most likely
/// watch now (`HomePicks`) big, over its picture, with Play ready — and
/// its own short list of the others along the bottom. Moving along that
/// list brings each one up (the TV's focus, the Mac's pointer, a tap) and
/// selecting one plays it. Nothing else on the page changes what's up
/// here: the rows below are their own.
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

    /// Nearly the screen: the TV leaves the first row's title showing
    /// below; elsewhere it follows the page's shape.
    private var height: CGFloat {
        switch Layout.device {
        case .tv: 820
        case .phone: 560
        default: max(440, min(width * 0.52, 700))
        }
    }
    /// The picture runs up under the page's top padding, to the edge.
    private var bleed: CGFloat { Platform.isTV ? 110 : 18 }
    private var listCardWidth: CGFloat { Layout.device == .tv ? 260 : compact ? 120 : 180 }

    var body: some View {
        if let pick = shown {
            ZStack(alignment: .bottomLeading) {
                backdrop(pick.item)
                VStack(alignment: .leading, spacing: Platform.isTV ? 40 : 20) {
                    // Across the whole width: Up from anywhere along the list lands on Play.
                    words(pick)
                        .frame(maxWidth: compact ? .infinity : width * 0.55, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tvFocusSection()
                    if picks.count > 1 { list }
                }
                .padding(.bottom, Platform.isTV ? 24 : 12)
            }
            .frame(height: height, alignment: .bottom)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.pick")
            // On the TV a pick comes up as focus reaches it in the list (only
            // there: the rows below never change it).
            .onChange(of: tracker?.featured?.id) { _, id in
                guard Platform.isTV, tracker?.row == Self.row, let id, picks.contains(where: { $0.id == id }) else { return }
                chosen = id
            }
            .onChange(of: picks.map(\.id)) { _, ids in if let chosen, !ids.contains(chosen) { self.chosen = nil } }
            // Every pick's picture and logo in memory before it's brought up:
            // moving along the list swaps drawn images, never loads them.
            .task(id: picks.map(\.id)) { prefetch() }
        }
    }

    private func prefetch() {
        guard let client else { return }
        let logoWidth = HeroLogo.box(for: Layout.device).width
        let requests = picks.flatMap { pick in
            // The backdrop at the size FocusBackdrop asks for, so it's the same image.
            [ArtworkSource.resolve(pick.item, .backdrop)?.request(client: client, pixelWidth: 1920),
             ArtworkSource.resolve(pick.item, .logo)?.request(client: client, pixelWidth: Int(logoWidth * scale)),
             ArtworkSource.resolve(pick.item, .landscape)?.request(client: client, pixelWidth: Int(listCardWidth * scale))].compactMap { $0 }
        }
        ImagePipeline.shared.prefetch(requests)
    }

    /// The pick's picture, edge to edge, fading into the page at the foot.
    /// FocusBackdrop: image over image as picks change, never a dip between.
    private func backdrop(_ item: BaseItem) -> some View {
        FocusBackdrop(item)
            .frame(width: width + 2 * Layout.horizontalMargin, height: height + bleed)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.62), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .clipped()
            .padding(.horizontal, -Layout.horizontalMargin)
            .padding(.top, -bleed)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The others (and the one that's up), each with why it's here.
    private var list: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Layout.cardSpacing) {
                ForEach(picks) { pick in
                    let up = pick.id == shown?.id
                    LandscapeCard(pick.item, width: listCardWidth, kind: .landscape, caption: pick.reason) {
                        // Brought up already (focus, the pointer, an earlier tap): Select plays it.
                        if Platform.isTV || up { app.play(pick.item) } else { withAnimation(.smooth(duration: 0.25)) { chosen = pick.id } }
                    }
                    .opacity(up ? 1 : 0.6)
                    .animation(.easeOut(duration: 0.2), value: up)
                    .contextMenu { ItemContextMenu(item: pick.item) }
                    .reportsFocus(pick.item, row: Self.row)
                    #if !os(tvOS)
                    .onHover { inside in if inside { chosen = pick.id } }
                    #endif
                    .accessibilityIdentifier("card.picks.\(pick.id)")
                }
            }
            .scrollTargetLayout()
        }
        .homeRow()
        .tvFocusSection()
    }

    // MARK: Parts

    /// Why it's here, the title (its logo when there is one), and for an
    /// episode just which one — its words are spoilers and its page is the
    /// show's; for a film what it is and what it's about. Then Resume (with
    /// what's left), Start Over when it's been started, and Go to.
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
                if item.resumePosition != nil {
                    Pill("Start Over", systemImage: "gobackward") { app.play(item, resume: false) }
                        .pillCaption("Start Over")
                        .accessibilityIdentifier("home.pick.startOver")
                }
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
}
