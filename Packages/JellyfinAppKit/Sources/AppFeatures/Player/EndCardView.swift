import AppCore
import DesignSystem
import JellyfinAPI
import SwiftUI

/// At the credits: what now. Keep going (counting down, then by itself),
/// the next in another of your shows, something different, or done for
/// tonight — each with how long it is, when it would end and what it's
/// about — over the credits as they roll (Keep the Credits lets them), else
/// over the last frame. The same card on every platform: across on the TV,
/// iPad and Mac, stacked on a phone.
struct EndCardView: View {
    let card: EndCard
    let controller: PlayerController
    var focus: FocusState<PlayerView.PlayerFocus?>.Binding
    @Environment(\.theme) private var theme
    @Environment(\.hideSpoilers) private var hideSpoilers
    /// Focus is on the first choice: from here a move is you, not the card.
    @State private var settled = false

    private var tv: Bool { Platform.isTV }
    private var phone: Bool { Layout.device == .phone }

    var body: some View {
        let item = controller.item
        VStack(spacing: tv ? 44 : 22) {
            VStack(spacing: tv ? 8 : 3) {
                Text("That was \(Self.thatWas(item))")
                    .font(tv ? .callout : .footnote)
                    .foregroundStyle(.white.opacity(0.65))
                Text("What now?").font(tv ? .title2.bold() : .title3.bold())
            }
            let layout = phone ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: tv ? 32 : 14))
            layout {
                if let next = card.next {
                    let words = ItemAbout.nextLines(next, after: item)
                    EndChoice(kicker: card.countdown > 0 && !card.held ? "Keep going · in \(card.countdown) s" : "Keep going",
                              title: words.title, detail: words.detail, facts: facts(next), about: next.overview(hidingSpoilers: hideSpoilers),
                              art: next, accent: theme.accent,
                              progress: card.held ? nil : Double(card.countdown) / Double(EndCard.seconds), id: "end-next", focus: focus) {
                        Task { await controller.keepGoing() }
                    }
                }
                if let another = card.another {
                    EndChoice(kicker: "Next in your shows", title: another.seriesName ?? another.name ?? "",
                              detail: [another.episodeLabel, another.seriesName == nil ? nil : another.name].compactMap { $0 }.joined(separator: " · "),
                              facts: facts(another), about: another.overview(hidingSpoilers: hideSpoilers),
                              art: another, id: "end-another", focus: focus) {
                        Task { await controller.playAnother() }
                    }
                }
                if let instead = card.instead {
                    EndChoice(kicker: "Something different", title: instead.name ?? "", detail: Self.why(instead, after: item),
                              facts: facts(instead), about: instead.overview(hidingSpoilers: hideSpoilers),
                              art: instead, id: "end-instead", focus: focus) {
                        Task { await controller.playInstead() }
                    }
                }
                EndChoice(kicker: nil, title: "Done for tonight", detail: Self.doneDetail(card.next), symbol: "moon.zzz",
                          id: "end-done", focus: focus) {
                    Task { await controller.doneForTonight() }
                }
            }
            .fixedSize(horizontal: false, vertical: true)       // all as tall as the tallest
            .frame(maxWidth: phone ? .infinity : (tv ? 1720 : 1100))
            if card.atCredits {
                Button("Keep the Credits") { controller.keepCredits() }
                    .font(tv ? .callout : .footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    #if !os(tvOS)
                    .buttonStyle(.plain)
                    #endif
                    .focused(focus, equals: .option("end-credits"))
                    .accessibilityIdentifier("option.end-credits")
            }
        }
        .padding(.horizontal, phone ? 16 : 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(card.atCredits ? 0.72 : 0.94).ignoresSafeArea())
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .tvFocusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.endCard")
        .task {
            // Onto the first choice once it's in the focus graph.
            for _ in 0..<5 where !Self.isChoice(focus.wrappedValue) {
                focus.wrappedValue = .option(card.next != nil ? "end-next" : card.another != nil ? "end-another" : card.instead != nil ? "end-instead" : "end-done")
                try? await Task.sleep(for: .milliseconds(40))
            }
            settled = true
        }
        // Moving the remote (or the arrow keys) stops the countdown: you're choosing.
        .onChange(of: focus.wrappedValue) { _, _ in if settled { controller.holdCountdown() } }
        #if !os(iOS)
        .onMoveCommand { _ in controller.holdCountdown() }
        #endif
    }

    private static func isChoice(_ f: PlayerView.PlayerFocus?) -> Bool {
        if case .option(let id) = f { return id.hasPrefix("end-") }
        return false
    }

    /// "43 min · ★ 8.1 · ends 10:58 PM": how long, how liked, and when it
    /// would end if it started after this one.
    private func facts(_ other: BaseItem) -> String? {
        var parts: [String] = []
        if let runtime = other.runtime { parts.append(MetadataLine.runtimeString(runtime)) }
        if let score = other.communityRating { parts.append("★ " + score.formatted(.number.precision(.fractionLength(1)))) }
        if let end = controller.upNextEnds([other]).first, other.runtime != nil {
            parts.append("ends " + end.formatted(date: .omitted, time: .shortened))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Season 1, Episode 4"; a film by its name.
    static func thatWas(_ item: BaseItem) -> String {
        if item.kind == .episode, let s = item.parentIndexNumber, let e = item.indexNumber { return "Season \(s), Episode \(e)" }
        return item.name ?? "it"
    }

    /// Why this one: a film and its year; another show's name; else what it's like.
    static func why(_ other: BaseItem, after item: BaseItem) -> String? {
        var parts: [String] = []
        if other.kind == .movie { parts.append("Film") }
        if other.kind == .series || other.kind == .episode, let show = other.seriesName ?? other.name, show != other.name { parts.append(show) }
        if let year = other.productionYear { parts.append(String(year)) }
        if parts.isEmpty, let show = item.seriesName ?? item.name { return "Like \(show)" }
        return parts.joined(separator: " · ")
    }

    static func doneDetail(_ next: BaseItem?) -> String {
        guard let next else { return "Your place is kept on every device" }
        return "\(next.kind == .episode ? "The next episode" : (next.name ?? "What's next")) waits on Home"
    }
}

/// One of the end card's choices: a picture (or a symbol), what it is, and
/// for Keep Going the countdown along its foot.
private struct EndChoice: View {
    let kicker: String?
    let title: String
    let detail: String?
    /// "43 min · ★ 8.1 · ends 10:58 PM".
    var facts: String? = nil
    /// What it's about (none when Hide Spoilers keeps it back).
    var about: String? = nil
    var art: BaseItem? = nil
    var symbol: String? = nil
    var accent: Color? = nil
    var progress: Double? = nil
    let id: String
    var focus: FocusState<PlayerView.PlayerFocus?>.Binding
    let action: () -> Void

    private var tv: Bool { Platform.isTV }
    private var phone: Bool { Layout.device == .phone }

    var body: some View {
        Button(action: action) { Face(choice: self) }
            .buttonStyle(BareButtonStyle())
            .focused(focus, equals: .option(id))
            .accessibilityIdentifier("option.\(id)")
    }

    private struct Face: View {
        let choice: EndChoice
        @Environment(\.isFocused) private var focused

        var body: some View {
            let tv = choice.tv, phone = choice.phone
            let artWidth: CGFloat = tv ? 380 : (phone ? 112 : 240)
            let stack = phone ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: tv ? 16 : 10))
            stack {
                Group {
                    if let art = choice.art {
                        Artwork(item: art, kind: .landscape, width: artWidth)
                    } else {
                        Image(systemName: choice.symbol ?? "circle")
                            .font(.system(size: tv ? 64 : (phone ? 22 : 34), weight: .light))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.white.opacity(0.08))
                    }
                }
                .frame(width: phone ? artWidth : nil, height: phone ? artWidth * 9 / 16 : nil)
                .frame(maxWidth: phone ? nil : .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(.rect(cornerRadius: tv ? 16 : 9))
                VStack(alignment: .leading, spacing: tv ? 4 : 2) {
                    if let kicker = choice.kicker {
                        Text(kicker)
                            .textCase(.uppercase)
                            .font((tv ? Font.caption : .caption2).weight(.bold))
                            .foregroundStyle(choice.accent ?? .white.opacity(0.6))
                            .contentTransition(.numericText(countsDown: true))
                    }
                    Text(choice.title).font(tv ? .headline : .subheadline.weight(.bold)).lineLimit(2)
                    if let detail = choice.detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                    }
                    if let facts = choice.facts {
                        Text(facts).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                            .padding(.top, tv ? 4 : 2)
                    }
                    if let about = choice.about, !about.isEmpty {
                        Text(about).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(phone ? 2 : 3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, tv ? 6 : 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(tv ? 18 : 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.white.opacity(tv && focused ? 0.2 : 0.09), in: .rect(cornerRadius: tv ? 24 : 14))
            .overlay(alignment: .bottom) {
                if let progress = choice.progress, progress > 0 {
                    GeometryReader { g in
                        Rectangle().fill(choice.accent ?? .white).frame(width: g.size.width * progress, height: 3)
                            .animation(.linear(duration: 1), value: progress)
                    }
                    .frame(height: 3)
                }
            }
            .clipShape(.rect(cornerRadius: tv ? 24 : 14))
            .overlay {
                if let accent = choice.accent, !tv || !focused {
                    RoundedRectangle(cornerRadius: tv ? 24 : 14).stroke(accent, lineWidth: 2)
                }
            }
            .scaleEffect(tv && focused ? 1.05 : 1)
            .shadow(color: .black.opacity(tv && focused ? 0.5 : 0), radius: 24, y: 12)
            .animation(.easeOut(duration: 0.15), value: focused)
            .contentShape(.rect)
        }
    }
}
