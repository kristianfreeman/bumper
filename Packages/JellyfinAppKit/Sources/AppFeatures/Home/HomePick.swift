import AppCore
import DesignSystem
import JellyfinAPI
import SwiftUI

/// Home's lead, the top of the page: the one thing you'd most likely watch
/// now (`HomePicks`) over its picture, with Play ready. The rows below are
/// their own: nothing in them changes it.
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

    static let row = "picks"
    private var compact: Bool { width < 700 }
    private var shown: HomePicks.Pick? { picks.first }

    /// The top of the page, not all of it: the first row shows below it,
    /// and the next one's title.
    private var height: CGFloat {
        switch Layout.device {
        case .tv: 560
        case .phone: 420
        default: max(340, min(width * 0.4, 520))
        }
    }
    /// The picture runs up under the page's top padding, to the edge.
    private var bleed: CGFloat { Platform.isTV ? 110 : 18 }

    var body: some View {
        if let pick = shown {
            ZStack(alignment: .bottomLeading) {
                backdrop(pick.item)
                VStack(alignment: .leading, spacing: Platform.isTV ? 40 : 20) {
                    // Across the whole width: Up from anywhere along the row below lands on Play.
                    words(pick)
                        .frame(maxWidth: compact ? .infinity : width * 0.55, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tvFocusSection()
                }
                .padding(.bottom, Platform.isTV ? 24 : 12)
            }
            .frame(height: height, alignment: .bottom)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.pick")
            // Its picture and logo in memory before the page shows it.
            .task(id: picks.map(\.id)) { prefetch() }
        }
    }

    private func prefetch() {
        guard let client else { return }
        let logoWidth = HeroLogo.box(for: Layout.device).width
        let requests = picks.prefix(1).flatMap { pick in
            // The backdrop at the size FocusBackdrop asks for, so it's the same image.
            [ArtworkSource.resolve(pick.item, .backdrop)?.request(client: client, pixelWidth: 1920),
             ArtworkSource.resolve(pick.item, .logo)?.request(client: client, pixelWidth: Int(logoWidth * scale))].compactMap { $0 }
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
