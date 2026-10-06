import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import PlaybackCore
import SwiftUI

/// The menus the icon row above the timeline opens. Playback holds
/// Background and the sleep timer (which live only here: they're about
/// what's playing).
enum PlayerMenu: String, CaseIterable, Hashable {
    case subtitles, audio, playback, info

    var symbol: String {
        switch self {
        case .subtitles: "captions.bubble"
        case .audio: "speaker.wave.2"
        case .playback: "gearshape"
        case .info: "info.circle"
        }
    }

    var title: String {
        switch self {
        case .subtitles: "Subtitles"
        case .audio: "Audio"
        case .playback: "Playback"
        case .info: "Info"
        }
    }
}

/// A short-lived glyph confirming a press (pause, play, ±10 s).
struct Flash: Equatable {
    enum Edge { case leading, center, trailing }
    let id = UUID()
    let symbol: String
    let edge: Edge
}

extension Flash {
    init(_ kind: TransportModel.Feedback.Kind) {
        switch kind {
        case .play: self.init(symbol: "play.fill", edge: .center)
        case .pause: self.init(symbol: "pause.fill", edge: .center)
        case .skipBack: self.init(symbol: "gobackward.10", edge: .leading)
        case .skipForward: self.init(symbol: "goforward.10", edge: .trailing)
        }
    }
}

struct FlashView: View {
    let flash: Flash?

    var body: some View {
        ZStack {
            if let flash {
                let scale = Platform.isTV ? 1 : 0.6
                Image(systemName: flash.symbol)
                    .font(.system(size: (flash.edge == .center ? 64 : 48) * scale, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 150 * scale, height: 150 * scale)
                    .background(Color.black.opacity(0.55), in: .circle)
                    .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 2))
                    .frame(maxWidth: .infinity, alignment: alignment(flash.edge))
                    .padding(.horizontal, Platform.isTV ? 220 : 48)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .id(flash.id)
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.spring(duration: 0.25), value: flash)
        .allowsHitTesting(false)
    }

    private func alignment(_ edge: Flash.Edge) -> Alignment {
        switch edge {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// Legibility gradient behind the controls (bottom-heavy; top for the title).
struct ChromeScrim: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0.55), location: 0),
            .init(color: .clear, location: 0.22),
            .init(color: .clear, location: 0.5),
            .init(color: .black.opacity(0.85), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Bottom controls: what's playing (and how long until it ends), the icon
/// row, then the timeline (with the scrub preview riding above its head
/// while paused).
struct TransportBar: View {
    @Environment(AppModel.self) private var app
    let controller: PlayerController
    let engine: any PlayerEngine
    let scrubTime: Duration?
    let scrubThumb: CGImage?
    let openMenu: PlayerMenu?
    var focus: FocusState<PlayerView.PlayerFocus?>.Binding
    let open: (PlayerMenu) -> Void
    let leave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            HStack(alignment: .bottom, spacing: 40) {
                PlayingTitle(controller: controller, engine: engine)
                Spacer(minLength: 0)
                HStack(spacing: 18) {
                    ForEach(PlayerMenu.allCases, id: \.self) { menu in
                        Pill(menu.title, systemImage: menu.symbol + (openMenu == menu || lit(menu) ? ".fill" : ""),
                             detail: detail(menu), size: .small, active: lit(menu)) { open(menu) }
                            .accessibilityIdentifier("control.\(menu.rawValue)")
                            .focused(focus, equals: .control(menu))
                            // Down: back to the video — not while a card is open
                            // (a press before focus has moved into the card closed it).
                            .tvMoveCommand { if $0 == .down && openMenu == nil { leave() } }
                            .disabled(openMenu != nil && openMenu != menu)       // a card open: focus stays in it
                    }
                }
                // The row moves as one as a pill opens to show its name (as on
                // the detail page), instead of its neighbours jumping aside.
                .animation(.spring(duration: 0.3, bounce: 0.2), value: focus.wrappedValue)
                .tvFocusSection()
            }
            .padding(.bottom, 44)
            .opacity(scrubTime == nil ? 1 : 0)              // the preview takes this space
            .animation(.easeOut(duration: 0.15), value: scrubTime == nil)
            Timeline(time: controller.displayTime, duration: engine.duration ?? controller.item.runtime ?? .zero,
                     scrubTime: scrubTime, scrubThumb: scrubThumb, paused: engine.status == .paused,
                     seek: { t in Task { await controller.seek(to: t) } })
        }
        .padding(.horizontal, 90)
        .padding(.top, 60)
        .padding(.bottom, 64)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(engine.status == .paused ? "transport.paused" : "transport.playing")
    }

    /// Lit: subtitles on; Background or a sleep timer on.
    private func lit(_ menu: PlayerMenu) -> Bool {
        switch menu {
        case .subtitles: controller.selectedSubtitle != nil || controller.foundSubtitle != nil
        case .playback: controller.isBackground || app.sleepTimer.isActive
        default: false
        }
    }

    private func detail(_ menu: PlayerMenu) -> String? {
        guard menu == .playback else { return nil }
        return app.sleepTimer.shortLabel.map { "Sleep in \($0)" } ?? (controller.isBackground ? "Background" : nil)
    }
}

/// What's playing, said briefly: the show and episode, the title, and when
/// it ends — Background, when it's on, as a tag of its own.
struct PlayingTitle: View {
    let controller: PlayerController
    let engine: any PlayerEngine

    var body: some View {
        let phone = Layout.device == .phone
        VStack(alignment: .leading, spacing: phone ? 4 : 8) {
            if controller.isBackground {
                Label("Background", systemImage: "infinity")
                    .font((phone ? Font.caption : .callout).weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, phone ? 8 : 14)
                    .padding(.vertical, phone ? 3 : 5)
                    .background(.white.opacity(0.85), in: .capsule)
                    .accessibilityIdentifier("player.backgroundTag")
            }
            if let kicker { Text(kicker).font((phone ? Font.caption : .callout).weight(.semibold)).foregroundStyle(.white.opacity(0.75)).lineLimit(1) }
            Text(controller.item.name ?? "")
                .font(.system(size: Platform.isTV ? 48 : phone ? 19 : Layout.pageTitleSmall, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let ends {
                Text(ends).font((phone ? Font.caption : .callout).weight(.medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
        }
    }

    private var kicker: String? {
        let item = controller.item
        guard let series = item.seriesName else { return nil }
        if let s = item.parentIndexNumber, let e = item.indexNumber { return "\(series) · Season \(s), Episode \(e)" }
        return series
    }

    /// "Ends at 10:42 PM" (Background goes on, so no end).
    private var ends: String? {
        guard !controller.isBackground, let total = engine.duration ?? controller.item.runtime, total >= .seconds(60) else { return nil }
        let left = max(.zero, total - controller.displayTime)
        let end = Date.now.addingTimeInterval(left.seconds / Double(max(0.1, engine.rate)))
        return "Ends at " + end.formatted(date: .omitted, time: .shortened)
    }
}

/// Progress, times, and — while scrubbing — a frame preview above the head.
struct Timeline: View {
    let time: Duration
    let duration: Duration
    let scrubTime: Duration?
    let scrubThumb: CGImage?
    let paused: Bool
    /// Touch and the pointer: drag along the bar, let go to seek there.
    var seek: (Duration) -> Void = { _ in }
    @State private var dragging: Duration?

    private static let thumbSize = CGSize(width: 384 * Layout.pillScale, height: 216 * Layout.pillScale)

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                let width = geo.size.width
                let shown = dragging ?? scrubTime
                let played = fraction(time) * width
                let head = fraction(shown ?? time) * width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white.opacity(shown == nil ? 1 : 0.45)).frame(width: max(8, played))
                    if shown != nil {
                        Capsule().fill(.white).frame(width: 4, height: 34).offset(x: head - 2)
                    }
                    if let shown, scrubTime != nil || !Platform.isTV {
                        preview(shown)
                            .position(x: min(max(head, Self.thumbSize.width / 2), width - Self.thumbSize.width / 2), y: -Self.thumbSize.height / 2 - 54)
                    }
                }
                .frame(height: shown == nil ? 8 : 12)
                .frame(maxHeight: .infinity)
                .animation(.easeOut(duration: 0.12), value: shown == nil)
                .contentShape(.rect)
                #if !os(tvOS)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in dragging = at(g.location.x, width) }
                        .onEnded { g in
                            seek(at(g.location.x, width))
                            dragging = nil
                        }
                )
                #endif
            }
            .frame(height: 34)
            HStack {
                Text(time.clockString)
                Spacer()
                if paused && scrubTime == nil && Platform.isTV { Text("Swipe to scrub").foregroundStyle(.white.opacity(0.55)) }
                Spacer()
                Text("−" + max(.zero, duration - time).clockString)
            }
            .font(.callout.monospacedDigit().weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func preview(_ at: Duration) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Color.black.opacity(0.6)
                if let scrubThumb {
                    Image(decorative: scrubThumb, scale: 1).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ProgressView()
                }
            }
            .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            Text(at.clockString)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(.white, in: .capsule)
        }
        .accessibilityIdentifier("scrub.preview")
    }

    private func at(_ x: CGFloat, _ width: CGFloat) -> Duration {
        .seconds(duration.seconds * Double(min(1, max(0, x / max(1, width)))))
    }

    private func fraction(_ t: Duration) -> CGFloat {
        guard duration > .zero else { return 0 }
        return CGFloat(min(1, max(0, t.seconds / duration.seconds)))
    }
}

/// A button with no system focus platter: the label draws its own focus
/// state from `\.isFocused`.
struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// "Find Subtitles": searching, then what was found — the best first,
/// called out only when it's a clear fit; the rest by how well they match.
struct FoundSubtitles: View {
    let controller: PlayerController
    var focus: FocusState<PlayerView.PlayerFocus?>.Binding
    let close: () -> Void

    var body: some View {
        switch controller.subtitleSearch {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: 16) {
                ProgressView()
                Text("Searching…").foregroundStyle(.white.opacity(0.75))
            }
            .padding(20)
            .focusable()
            .focused(focus, equals: .option("sub-searching"))
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .padding(20)
                .focusable()
                .focused(focus, equals: .option("sub-failed"))
        case .results(let found):
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(found.enumerated()), id: \.element.id) { i, sub in
                        OptionRow(title: sub.name, detail: Self.detail(sub, best: i == 0), selected: controller.foundSubtitle?.id == sub.id,
                                  id: "found-\(sub.id)", focus: focus, highlighted: i == 0 && Self.isClearFit(sub)) {
                            Task { await controller.use(sub) }
                            close()
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .tvScrollClipDisabled()
            .frame(maxHeight: 560)
        }
    }

    /// Sure enough to say so.
    static func isClearFit(_ sub: FoundSubtitle) -> Bool { sub.confidence >= 0.8 }

    /// "Best match · 94%" for a clear fit at the top; else "46% match".
    static func detail(_ sub: FoundSubtitle, best: Bool) -> String {
        best && isClearFit(sub) ? "Best match · \(sub.confidenceText)" : "\(sub.confidenceText) match"
    }
}

/// The card a chrome icon opens, anchored above the icon row on the right.
/// Focus stays inside it (up and down its rows); Menu steps back out — from
/// found subtitles to the list, from the list to the icon.
struct MenuCard: View {
    @Environment(AppModel.self) private var app
    let menu: PlayerMenu
    let controller: PlayerController
    var focus: FocusState<PlayerView.PlayerFocus?>.Binding
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 26)
                .contentTransition(.opacity)
            content
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 10)
        .frame(width: menu == .info ? 900 : 600, alignment: .leading)
        .overVideoPanel(cornerRadius: 34)
        .tvFocusSection()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 90)
        .padding(.bottom, 270)
        .defaultFocus(focus, defaultOption)
        .animation(.spring(duration: 0.3), value: controller.subtitleSearch)
        .onChange(of: controller.subtitleSearch) { _, now in
            // Searching → results: focus onto the best match.
            guard now != .idle else { return }
            Task {
                for _ in 0..<5 {
                    try? await Task.sleep(for: .milliseconds(40))
                    focus.wrappedValue = defaultOption
                }
            }
        }
        .onDisappear { if controller.subtitleSearch != .idle { controller.subtitleSearch = .idle } }
        .task {
            // After the card's buttons are in the focus graph (an immediate
            // assignment can land before they exist and leave focus on the icon).
            for _ in 0..<5 where !isOption(focus.wrappedValue) {
                focus.wrappedValue = defaultOption
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    private var heading: String {
        if menu == .subtitles, controller.subtitleSearch != .idle { return "Found Subtitles" }
        return menu == .info ? (controller.item.kind == .episode ? "About This Episode" : "About This Film") : menu.title
    }

    @ViewBuilder
    private var content: some View {
        switch menu {
        case .subtitles:
            if controller.subtitleSearch == .idle {
                let rows = controller.subtitleOptions.count + 2 + (controller.foundSubtitle == nil ? 0 : 1)
                ScrollView {
                    VStack(spacing: 6) {
                        OptionRow(title: "Off", detail: nil, selected: controller.selectedSubtitle == nil && controller.foundSubtitle == nil, id: "sub-off", focus: focus) {
                            Task { await controller.selectSubtitle(nil) }
                            close()
                        }
                        ForEach(controller.subtitleOptions, id: \.index) { stream in
                            OptionRow(title: Self.trackName(stream), detail: Self.trackNote(stream), selected: controller.selectedSubtitle == stream.index,
                                      id: "sub-\(stream.index)", focus: focus) {
                                Task { await controller.selectSubtitle(stream.index) }
                                close()
                            }
                        }
                        if let found = controller.foundSubtitle {
                            OptionRow(title: found.name, detail: "\(found.confidenceText) match", selected: true, id: "sub-found", focus: focus) { close() }
                        }
                        OptionRow(title: "Find Subtitles…", detail: nil, selected: false, id: "sub-find", focus: focus, symbol: "magnifyingglass") {
                            Task { await controller.findSubtitles() }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .tvScrollClipDisabled()
                .frame(maxHeight: min(560, CGFloat(rows) * 84))
            } else {
                FoundSubtitles(controller: controller, focus: focus, close: close)
            }
        case .audio:
            VStack(spacing: 6) {
                ForEach(controller.audioOptions) { track in
                    OptionRow(title: track.title, detail: track.detail, selected: controller.engine?.selectedAudioTrack == track.id, id: "audio-\(track.id)", focus: focus) {
                        Task { await controller.selectAudio(track.id) }
                        close()
                    }
                }
            }
            .padding(.horizontal, 10)
        case .playback:
            let timer = app.sleepTimer
            VStack(alignment: .leading, spacing: 6) {
                OptionRow(title: "Background", detail: controller.isBackground ? "Plays on; nothing is marked watched" : nil, selected: false,
                          id: "background", focus: focus, symbol: "infinity", trailing: controller.isBackground ? "On" : "Off") {
                    controller.setBackground(!controller.isBackground)
                }
                Text("Sleep Timer")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 26)
                    .padding(.top, 14)
                OptionRow(title: "Off", detail: nil, selected: !timer.isActive, id: "sleep-off", focus: focus) {
                    timer.reset()
                    close()
                }
                ForEach(SleepTimer.presets, id: \.self) { minutes in
                    OptionRow(title: SleepTimer.title(minutes), detail: nil, selected: timer.mode == .minutes(minutes), id: "sleep-\(minutes)", focus: focus,
                              trailing: timer.mode == .minutes(minutes) ? timer.shortLabel.map { "\($0) left" } : nil) {
                        timer.set(.minutes(minutes))
                        close()
                    }
                }
                OptionRow(title: controller.item.kind == .episode ? "End of This Episode" : "End of This Film", detail: nil,
                          selected: timer.mode == .endOfItem, id: "sleep-end", focus: focus) {
                    timer.set(.endOfItem)
                    close()
                }
            }
            .padding(.horizontal, 10)
        case .info:
            ItemAbout(controller: controller)
                .padding(.horizontal, 26)
                .focusable()
                .focused(focus, equals: .option("info"))
        }
    }

    /// "English", "English (Forced)" — the language, not the stream's label.
    static func trackName(_ s: MediaStream) -> String {
        let name = s.language.flatMap { Locale.current.localizedString(forLanguageCode: $0) } ?? s.displayTitle ?? "Track \(s.index)"
        return s.isForced == true ? "\(name) (Forced)" : name
    }

    /// Only what tells two tracks apart: hearing-impaired, a title of its own.
    static func trackNote(_ s: MediaStream) -> String? {
        let label = (s.title ?? "") + " " + (s.displayTitle ?? "")
        if label.contains("SDH") || label.localizedCaseInsensitiveContains("hearing impaired") { return "SDH" }
        guard let title = s.title, !title.isEmpty, title.lowercased() != (s.language ?? "").lowercased() else { return nil }
        return title
    }

    private func isOption(_ f: PlayerView.PlayerFocus?) -> Bool {
        if case .option = f { true } else { false }
    }

    private var defaultOption: PlayerView.PlayerFocus {
        switch menu {
        case .subtitles:
            switch controller.subtitleSearch {
            case .results(let found): .option(found.first.map { "found-\($0.id)" } ?? "sub-find")
            case .searching: .option("sub-searching")
            case .failed: .option("sub-failed")
            case .idle: .option(controller.foundSubtitle != nil ? "sub-found" : controller.selectedSubtitle.map { "sub-\($0)" } ?? "sub-off")
            }
        case .audio: .option((controller.engine?.selectedAudioTrack ?? controller.audioOptions.first?.id).map { "audio-\($0)" } ?? "audio-none")
        case .playback: .option("background")
        case .info: .option("info")
        }
    }
}

/// A row in a card: the choice, a quiet line under it when it says
/// something, a check when it's the current one. Focused, it lifts — white,
/// a little larger, with a shadow — and its neighbours stay put.
private struct OptionRow: View {
    let title: String
    let detail: String?
    let selected: Bool
    let id: String
    var focus: FocusState<PlayerView.PlayerFocus?>.Binding
    /// A clear best match: in the accent.
    var highlighted = false
    var symbol: String? = nil
    /// A state at the end of the row ("On", "12m left").
    var trailing: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) { Face(title: title, detail: detail, selected: selected, highlighted: highlighted, symbol: symbol, trailing: trailing) }
            .buttonStyle(BareButtonStyle())
            .focused(focus, equals: .option(id))
            .accessibilityIdentifier("option.\(id)")
            .accessibilityValue(trailing ?? (selected ? "selected" : ""))
    }

    private struct Face: View {
        let title: String
        let detail: String?
        let selected: Bool
        let highlighted: Bool
        let symbol: String?
        let trailing: String?
        @Environment(\.isFocused) private var focused
        @Environment(\.theme) private var theme

        var body: some View {
            HStack(spacing: 16) {
                Group {
                    if let symbol { Image(systemName: symbol) } else { Image(systemName: "checkmark").opacity(selected ? 1 : 0) }
                }
                .font(.body.weight(.bold))
                .foregroundStyle(focused ? Color.black : selected || highlighted ? theme.accent : .white.opacity(0.8))
                .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(selected ? .semibold : .regular)).lineLimit(1).truncationMode(.middle)
                    if let detail {
                        Text(detail).font(.caption.weight(highlighted ? .bold : .medium))
                            .foregroundStyle(focused ? Color.black.opacity(0.6) : highlighted ? theme.accent : .white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).font(.callout.weight(.semibold).monospacedDigit()).opacity(0.7).contentTransition(.numericText())
                }
            }
            .foregroundStyle(focused ? .black : .white)
            .padding(.horizontal, 18)
            .padding(.vertical, detail == nil ? 16 : 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(focused ? Color.white : selected ? Color.white.opacity(0.07) : .clear, in: .rect(cornerRadius: 18, style: .continuous))
            .scaleEffect(focused ? 1.025 : 1)
            .shadowWhen(focused, color: .black.opacity(0.35), radius: 16, y: 6)
            .animation(.spring(duration: 0.22, bounce: 0.15), value: focused)
        }
    }
}

/// About what's playing: the art, what it is, what happens (spoiler-safe),
/// who's in it, and what's next.
struct ItemAbout: View {
    let controller: PlayerController
    @Environment(AppModel.self) private var app
    @Environment(\.jellyfin) private var client

    var body: some View {
        let item = controller.item
        let tv = Platform.isTV
        HStack(alignment: .top, spacing: tv ? 32 : 16) {
            Artwork(item: item, kind: item.kind == .episode ? .still : .backdrop, width: tv ? 300 : 120)
                .frame(width: tv ? 300 : 120, height: (tv ? 300 : 120) * 9 / 16)
                .clipShape(.rect(cornerRadius: tv ? 16 : 10))
            VStack(alignment: .leading, spacing: tv ? 10 : 6) {
                Text(item.name ?? "").font(tv ? .title3.weight(.bold) : .headline).lineLimit(2)
                Text(Self.facts(item)).font(tv ? .callout : .caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                if let overview = item.overview(hidingSpoilers: app.settings.hideSpoilers) {
                    Text(overview).font(tv ? .callout : .footnote).foregroundStyle(.white.opacity(0.85)).lineLimit(tv ? 5 : 6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let cast = Self.cast(item) {
                    Text(cast).font(tv ? .callout : .footnote).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                }
                if let next = controller.nextEpisode {
                    Label("Next: \([next.episodeLabel, next.name].compactMap { $0 }.joined(separator: " · "))", systemImage: "forward.end")
                        .font((tv ? Font.callout : .footnote).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.top, 4)
                }
            }
        }
        .foregroundStyle(.white)
    }

    /// "S2 · E3 · 2019 · 48 min · TV-14 · Drama, Mystery"
    static func facts(_ item: BaseItem) -> String {
        var parts: [String] = []
        if let label = item.episodeLabel { parts.append(label) }
        if let year = item.productionYear { parts.append(String(year)) }
        if let runtime = item.runtime { parts.append(MetadataLine.runtimeString(runtime)) }
        if let rating = item.officialRating, !rating.isEmpty { parts.append(rating) }
        if let genres = item.genres, !genres.isEmpty { parts.append(genres.prefix(2).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    /// "With Rhea Seehorn, Bob Odenkirk and Giancarlo Esposito · Directed by Vince Gilligan"
    static func cast(_ item: BaseItem) -> String? {
        let people = item.people ?? []
        let actors = people.filter { $0.type == "Actor" }.prefix(3).compactMap(\.name)
        let director = people.first { $0.type == "Director" }?.name
        var parts: [String] = []
        if !actors.isEmpty {
            parts.append("With " + (actors.count > 1 ? actors.dropLast().joined(separator: ", ") + " and " + actors.last! : actors[0]))
        }
        if let director { parts.append("Directed by \(director)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
