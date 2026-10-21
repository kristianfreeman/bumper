import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import PlaybackCore
import SwiftUI

/// What Up and Down open over the picture on the TV: Audio & Subtitles at
/// the top, More along the bottom.
enum CompassPanel: Hashable {
    case languages, more
}

/// More's tabs (the TV's panel, the sheet and the split's panel off it):
/// what it is, what you've lined up after it, and how it plays.
enum MoreTab: String, CaseIterable, Hashable, Identifiable {
    case info, upNext, playback

    var id: Self { self }

    var title: String {
        switch self {
        case .info: "Info"
        case .upNext: "Up Next"
        case .playback: "Playback"
        }
    }
}

/// A short-lived glyph confirming a press (pause, play, ±10 s).
struct Flash: Equatable {
    enum Edge { case leading, center, trailing }
    let id = UUID()
    let symbol: String
    let edge: Edge
    /// Presses in a row on the same side ("−30 s" after three).
    var count = 1
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

/// One badge per side, fixed in place: it fades in and out, and another
/// press on the same side bounces it (and counts up) instead of replacing
/// it. (One badge moved between sides slid across the screen, and each press
/// scaled a new one in over the old.)
struct FlashView: View {
    let flash: Flash?
    private let scale: CGFloat = Platform.isTV ? 1 : 0.6

    var body: some View {
        ZStack {
            ForEach([Flash.Edge.leading, .center, .trailing], id: \.self) { edge in
                Group {
                    if let flash, flash.edge == edge {
                        badge(flash).transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: alignment(edge))
            }
        }
        .padding(.horizontal, Platform.isTV ? 220 : 48)
        .frame(maxHeight: .infinity)
        .animation(.spring(duration: 0.25), value: flash?.edge)
        .allowsHitTesting(false)
    }

    private func badge(_ flash: Flash) -> some View {
        VStack(spacing: 12 * scale) {
            Image(systemName: flash.symbol)
                .font(.system(size: (flash.edge == .center ? 64 : 48) * scale, weight: .semibold))
                .symbolEffect(.bounce, value: flash.count)
                .foregroundStyle(.white)
                .frame(width: 150 * scale, height: 150 * scale)
                .background(Color.black.opacity(0.55), in: .circle)
                .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 2))
            if flash.count > 1, flash.edge != .center {
                Text("\(flash.edge == .leading ? "−" : "+")\(flash.count * 10) s")
                    .font(.system(size: 28 * scale, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .shadow(color: .black.opacity(0.6), radius: 6)
            }
        }
        .animation(.snappy(duration: 0.2), value: flash.count)
    }

    private func alignment(_ edge: Flash.Edge) -> Alignment {
        switch edge {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// A few plain words at the top of the picture for a few seconds (the
/// player changed something by itself: simpler subtitles).
struct PlayerNotice: View {
    let words: String?

    var body: some View {
        VStack {
            if let words {
                Text(words)
                    .font(Platform.isTV ? .callout : .subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Platform.isTV ? 28 : 16)
                    .padding(.vertical, Platform.isTV ? 14 : 9)
                    .overVideoPanel(cornerRadius: Platform.isTV ? 24 : 16)
                    .accessibilityIdentifier("player.notice")
                    .transition(.opacity)
            }
        }
        .padding(.top, Platform.isTV ? 70 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.25), value: words)
        .allowsHitTesting(false)
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

/// The TV's controls, in the title-safe area like the system player's: the
/// timeline along the foot with quiet words under it — the time, More (Down)
/// in the middle, what's left and when it ends — and Audio & Subtitles (Up)
/// at the top. Left and Right skip 10 s, said nowhere (everyone knows); in an
/// intro, Skip Intro sits over the timeline's end, and Right does it. None of
/// it takes focus: the remote acts on the video, and Up and Down open panels.
struct CompassChrome: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    let controller: PlayerController
    let engine: any PlayerEngine
    let scrubTime: Duration?
    let scrubThumb: CGImage?
    /// The hints and the timeline (false: a segment's Skip alone).
    let full: Bool
    /// "Skip Intro" while one plays: Right does it.
    let segment: String?

    var body: some View {
        let length = engine.duration ?? controller.item.runtime ?? .zero
        VStack(spacing: 0) {
            if full {
                Hint(symbol: "chevron.up", title: "Audio & Subtitles", detail: subtitles)
                    .accessibilityIdentifier("edge.up")
            }
            Spacer(minLength: 0)
            if let segment {
                Text(segment)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 12)
                    .background(theme.accent, in: .capsule)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.bottom, full ? 28 : 0)
                    .accessibilityIdentifier("edge.right")
            }
            if full {
                Timeline(time: controller.displayTime, duration: length, scrubTime: scrubTime, scrubThumb: scrubThumb,
                         paused: engine.status == .paused, showsTimes: false)
                HStack(alignment: .firstTextBaseline) {
                    Text(controller.displayTime.clockString)
                    Spacer()
                    Hint(symbol: "chevron.down", title: "More", detail: more)
                        .opacity(scrubTime == nil ? 1 : 0)
                        .accessibilityIdentifier("edge.down")
                    Spacer()
                    Text(remaining(length))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.62))
                .padding(.top, 10)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(!full ? "transport.hidden" : engine.status == .paused ? "transport.paused" : "transport.playing")
    }

    /// "English", "Off" — the language alone, not the track's whole label.
    private var subtitles: String {
        if controller.foundSubtitle != nil { return "Found" }
        guard let index = controller.selectedSubtitle, let stream = controller.subtitleOptions.first(where: { $0.index == index }) else { return "Off" }
        return TrackNames.language(stream)
    }

    /// With a sleep timer on, when it stops.
    private var more: String? {
        let timer = app.sleepTimer
        return timer.mode == .endOfItem ? "Stops after this" : timer.shortLabel.map { "Stops in \($0)" }
    }

    /// "−28:56 · Ends 10:15 PM" (playing in the background, no end).
    private func remaining(_ length: Duration) -> String {
        let left = max(.zero, length - controller.displayTime)
        guard !controller.isBackground, length >= .seconds(60) else { return "−" + left.clockString }
        let end = Date.now.addingTimeInterval(left.seconds / Double(max(0.1, engine.rate)))
        return "−" + left.clockString + "  ·  Ends " + end.formatted(date: .omitted, time: .shortened)
    }
}

/// A quiet word on what a press does: a small chevron the way to press, what
/// it opens, and how it stands, set softly over the picture.
private struct Hint: View {
    let symbol: String
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.caption2.weight(.bold)).opacity(0.7)
            Text(title).fontWeight(.medium)
            if let detail { Text(detail).opacity(0.6) }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.75))
        .shadow(color: .black.opacity(0.5), radius: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(detail ?? "")
    }
}

/// Progress, times, and — while scrubbing — a frame preview above the head.
struct Timeline: View {
    let time: Duration
    let duration: Duration
    let scrubTime: Duration?
    let scrubThumb: CGImage?
    let paused: Bool
    /// The times under the bar (the TV sets its own, with More between them).
    var showsTimes = true
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
                        // Hung from its foot, clear of the bar.
                        Color.clear.frame(width: 0, height: 0)
                            .overlay(alignment: .bottom) { preview(shown).fixedSize() }
                            .position(x: min(max(head, Self.thumbSize.width / 2), width - Self.thumbSize.width / 2), y: -34)
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
            if showsTimes {
                HStack {
                    Text(time.clockString)
                    Spacer()
                    Text("−" + max(.zero, duration - time).clockString)
                }
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
            }
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
        // A container of its own: an identifier on the bare stack was
        // stamped on every piece of it.
        .accessibilityElement(children: .contain)
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

/// Onto `target` once a panel's buttons are in the focus graph (an
/// immediate assignment can land before they exist and leave focus behind).
private struct FocusOnAppear: ViewModifier {
    var focus: FocusState<PlayerView.PlayerFocus?>.Binding
    let target: PlayerView.PlayerFocus
    let isInside: (PlayerView.PlayerFocus?) -> Bool

    func body(content: Content) -> some View {
        content
            .defaultFocus(focus, target)
            .task {
                for _ in 0..<5 where !isInside(focus.wrappedValue) {
                    focus.wrappedValue = target
                    try? await Task.sleep(for: .milliseconds(40))
                }
            }
    }
}

/// Up on the TV: Audio & Subtitles, as the system's own player has it — the
/// subtitles and the audio side by side, a check on each one playing.
/// Choosing one closes it; Left and Right go between the two. Find
/// Subtitles searches the server, and what it finds takes the Subtitles
/// column (Menu steps back to the list).
struct LanguagesCard: View {
    let controller: PlayerController
    var focus: FocusState<PlayerView.PlayerFocus?>.Binding
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            column(controller.subtitleSearch == .idle ? "Subtitles" : "Found Subtitles") {
                SubtitleOptions(controller: controller, focus: focus, close: close)
            }
            column("Audio") {
                AudioOptions(controller: controller, focus: focus, close: close)
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 10)
        .overVideoPanel(cornerRadius: 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        .modifier(FocusOnAppear(focus: focus, target: defaultOption) { if case .option = $0 { true } else { false } })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.languages")
    }

    private func column<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 26)
                .contentTransition(.opacity)
            content()
        }
        .frame(width: 560, alignment: .topLeading)
        .tvFocusSection()
    }

    /// The subtitle playing (or what a search found), so Up and Down go to the ones either side.
    private var defaultOption: PlayerView.PlayerFocus {
        switch controller.subtitleSearch {
        case .results(let found): .option(found.first.map { "found-\($0.id)" } ?? "sub-find")
        case .searching: .option("sub-searching")
        case .failed: .option("sub-failed")
        case .idle: .option(controller.foundSubtitle != nil ? "sub-found" : controller.selectedSubtitle.map { "sub-\($0)" } ?? "sub-off")
        }
    }
}

/// Off, each track, what a search found, and Find Subtitles — or, while
/// searching, what it's finding.
private struct SubtitleOptions: View {
    let controller: PlayerController
    var focus: FocusState<PlayerView.PlayerFocus?>.Binding
    let close: () -> Void

    var body: some View {
        if controller.subtitleSearch == .idle {
            let rows = controller.subtitleOptions.count + 2 + (controller.foundSubtitle == nil ? 0 : 1)
            ScrollView {
                VStack(spacing: 6) {
                    OptionRow(title: "Off", detail: nil, selected: controller.selectedSubtitle == nil && controller.foundSubtitle == nil, id: "sub-off", focus: focus) {
                        Task { await controller.selectSubtitle(nil) }
                        close()
                    }
                    ForEach(controller.subtitleOptions, id: \.index) { stream in
                        OptionRow(title: TrackNames.name(stream), detail: TrackNames.note(stream), selected: controller.selectedSubtitle == stream.index,
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
    }
}

/// Each audio track, the one playing checked.
private struct AudioOptions: View {
    let controller: PlayerController
    var focus: FocusState<PlayerView.PlayerFocus?>.Binding
    let close: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(controller.audioOptions) { track in
                OptionRow(title: track.title, detail: track.detail, selected: controller.engine?.selectedAudioTrack == track.id, id: "audio-\(track.id)", focus: focus) {
                    Task { await controller.selectAudio(track.id) }
                    close()
                }
            }
        }
        .padding(.horizontal, 10)
    }
}

/// How a track is named in the menus (and on the phone remote).
enum TrackNames {
    /// "English", "English (Forced)" — the language, not the stream's label.
    static func name(_ s: MediaStream) -> String {
        let name = s.language.flatMap { Locale.current.localizedString(forLanguageCode: $0) } ?? s.displayTitle ?? "Track \(s.index)"
        return s.isForced == true ? "\(name) (Forced)" : name
    }

    /// "English" — the language alone (the stream's label's first part when
    /// it has none), for saying what's on.
    static func language(_ s: MediaStream) -> String {
        if let code = s.language, let name = Locale.current.localizedString(forLanguageCode: code) { return name }
        let label = s.displayTitle ?? s.title ?? "Track \(s.index)"
        return label.components(separatedBy: " - ").first ?? label
    }

    /// Only what tells two tracks apart: hearing-impaired, a title of its own.
    static func note(_ s: MediaStream) -> String? {
        let label = (s.title ?? "") + " " + (s.displayTitle ?? "")
        if label.contains("SDH") || label.localizedCaseInsensitiveContains("hearing impaired") { return "SDH" }
        guard let title = s.title, !title.isEmpty, title.lowercased() != (s.language ?? "").lowercased() else { return nil }
        return title
    }
}

/// Down on the TV: More — what it is (Info), what you've lined up after it
/// (Up Next, only when you have), and how it plays (Playback: the sleep
/// timer, and Speakers when that's on). Focus on a tab shows it, as
/// tabs do on the TV; Down goes into it, Up from the tabs closes. Opens on Info.
struct MorePanel: View {
    @Environment(AppModel.self) private var app
    let controller: PlayerController
    var focus: FocusState<PlayerView.PlayerFocus?>.Binding
    let close: () -> Void
    @State private var tab: MoreTab = .info

    static func tabs(_ controller: PlayerController) -> [MoreTab] {
        MoreTab.allCases.filter { $0 != .upNext || !controller.chosenUpNext.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 14) {
                ForEach(Self.tabs(controller)) { t in
                    Button { focus.wrappedValue = into(t) } label: { TabFace(title: t.title, selected: tab == t) }
                        .buttonStyle(BareButtonStyle())
                        .focused(focus, equals: .tab(t))
                        .tvMoveCommand { if $0 == .up { close() } }
                        .accessibilityIdentifier("tab.\(t.rawValue)")
                        .accessibilityAddTraits(tab == t ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
            .tvFocusSection()
            Group {
                switch tab {
                case .info: ItemAbout(controller: controller).padding(.horizontal, 16)
                case .upNext: UpNextRow(controller: controller, focus: focus, close: close)
                case .playback: PlaybackOptions(controller: controller, focus: focus, close: close)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
        .padding(.top, 40)
        // Pinned to the foot of the screen: the content in the title-safe
        // area, the dark under it running to the edges.
        .background {
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0),
                                   .init(color: .black.opacity(0.8), location: 0.3),
                                   .init(color: .black.opacity(0.88), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .padding(.top, -90)
                .ignoresSafeArea(edges: [.horizontal, .bottom])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeInOut(duration: 0.2), value: tab)
        .onChange(of: focus.wrappedValue) { _, now in if case .tab(let t) = now { tab = t } }
        .modifier(FocusOnAppear(focus: focus, target: .tab(.info)) { now in
            switch now {
            case .tab, .option: true
            default: false
            }
        })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.more")
    }

    /// Select on a tab: into it, onto what you'd most likely want there.
    private func into(_ t: MoreTab) -> PlayerView.PlayerFocus {
        switch t {
        case .info: .tab(.info)
        case .upNext: .option(controller.chosenUpNext.first.map { "next-\($0.id)" } ?? "next-none")
        case .playback: .option(PlaybackOptions.current(app.sleepTimer))
        }
    }

    private struct TabFace: View {
        let title: String
        let selected: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(focused ? Color.black : selected ? .white : .white.opacity(0.65))
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(focused ? Color.white : selected ? Color.white.opacity(0.18) : .clear, in: .capsule)
                .scaleEffect(focused ? 1.06 : 1)
                .animation(.spring(duration: 0.22, bounce: 0.15), value: focused)
        }
    }
}

/// Up Next on the TV: what you've lined up after this one, across, each
/// with when it would end; Select plays it now. (Adding is the phone app's.)
private struct UpNextRow: View {
    let controller: PlayerController
    var focus: FocusState<PlayerView.PlayerFocus?>.Binding
    let close: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let list = controller.chosenUpNext
        let ends = controller.upNextEnds(list, now: app.queue.now)
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 40) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, next in
                    let words = ItemAbout.nextLines(next, after: controller.item)
                    let end = i < ends.count ? "ends \(ends[i].formatted(date: .omitted, time: .shortened))" : nil
                    Button {
                        app.play(next)
                        close()
                    } label: {
                        Tile(item: next, title: words.title, detail: [words.detail, end].compactMap { $0 }.joined(separator: " · "))
                    }
                    .buttonStyle(BareButtonStyle())
                    .focused(focus, equals: .option("next-\(next.id)"))
                    .accessibilityIdentifier("option.next-\(next.id)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .tvScrollClipDisabled()
    }

    /// Its clean art (an episode's show's, not a still), the words on the
    /// picture over a fade deep enough to read them.
    private struct Tile: View {
        let item: BaseItem
        let title: String
        let detail: String
        @Environment(\.isFocused) private var focused

        var body: some View {
            Artwork(item: item, kind: .backdrop, width: 400)
                .frame(width: 400, height: 225)
                .overlay {
                    LinearGradient(stops: [.init(color: .clear, location: 0.25), .init(color: .black.opacity(0.88), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(detail).font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                    .padding(18)
                }
                .clipShape(.rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white, lineWidth: focused ? 5 : 0))
                .foregroundStyle(.white)
                .scaleEffect(focused ? 1.06 : 1)
                .shadowWhen(focused, color: .black.opacity(0.45), radius: 22, y: 10)
                .animation(.spring(duration: 0.22, bounce: 0.15), value: focused)
        }
    }
}

/// Playback on the TV: Speakers (when that's on) and where else it can be
/// controlled from on the left, when to stop on the right.
private struct PlaybackOptions: View {
    let controller: PlayerController
    var focus: FocusState<PlayerView.PlayerFocus?>.Binding
    let close: () -> Void
    @Environment(AppModel.self) private var app

    /// The sleep timer's row for what it's set to.
    static func current(_ timer: SleepTimer) -> String {
        switch timer.mode {
        case .off: "sleep-off"
        case .endOfItem: "sleep-end"
        case .minutes(let m): SleepTimer.presets.contains(m) ? "sleep-\(m)" : "sleep-off"
        }
    }

    var body: some View {
        let timer = app.sleepTimer
        HStack(alignment: .top, spacing: 24) {
            if app.settings.speakersButton || app.settings.allowRemote {
                VStack(alignment: .leading, spacing: 20) {
                    if app.settings.speakersButton {
                        // The system's own picker: it focuses and presents itself
                        // (a hidden one pressed from a button of ours didn't).
                        HStack(spacing: 20) {
                            SpeakerPickerButton(size: 66)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Speakers").font(.body)
                                Text("Choose where the sound plays").font(.caption).foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }
                    if app.settings.allowRemote {
                        // Not a button: where else this can be played from.
                        HStack(spacing: 20) {
                            Image(systemName: "iphone").font(.title3).frame(width: 66)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Control this with your iPhone").font(.body)
                                Text("Open Bumper on an iPhone or iPad on this Wi-Fi").font(.caption).foregroundStyle(.white.opacity(0.55))
                            }
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("player.remoteHint")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .frame(width: 620, alignment: .topLeading)
                .tvFocusSection()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Stop Playing")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 26)
                    .padding(.bottom, 4)
                OptionRow(title: "Off", detail: nil, selected: !timer.isActive, id: "sleep-off", focus: focus) {
                    timer.reset()
                    close()
                }
                ForEach(SleepTimer.presets, id: \.self) { minutes in
                    OptionRow(title: SleepTimer.stopTitle(minutes), detail: nil, selected: timer.mode == .minutes(minutes), id: "sleep-\(minutes)", focus: focus,
                              trailing: timer.mode == .minutes(minutes) ? timer.shortLabel.map { "Stops in \($0)" } : nil) {
                        timer.set(.minutes(minutes))
                        close()
                    }
                }
                OptionRow(title: SleepTimer.afterTitle(controller.item.kind), detail: nil,
                          selected: timer.mode == .endOfItem, id: "sleep-end", focus: focus) {
                    timer.set(.endOfItem)
                    close()
                }
            }
            .frame(width: 560, alignment: .topLeading)
            .tvFocusSection()
        }
        .padding(.horizontal, 10)
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
    /// A state at the end of the row ("On", "Stops in 12m").
    var trailing: String? = nil
    /// The detail explains the row: shown only on it, not over the whole card.
    var detailWhenFocused = false
    /// A picture after the check.
    var thumbnail: AnyView? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Face(title: title, detail: detail, selected: selected, highlighted: highlighted, symbol: symbol, trailing: trailing,
                 detailWhenFocused: detailWhenFocused, thumbnail: thumbnail)
        }
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
        let detailWhenFocused: Bool
        let thumbnail: AnyView?
        @Environment(\.isFocused) private var focused
        @Environment(\.theme) private var theme
        /// A focus-only detail, changed in an animation: tvOS moves focus
        /// outside any, and the row (and the rows below it) jumped open.
        @State private var expanded = false
        private var showsDetail: Bool { detail != nil && (!detailWhenFocused || expanded) }

        var body: some View {
            HStack(spacing: 16) {
                Group {
                    if let symbol { Image(systemName: symbol) } else { Image(systemName: "checkmark").opacity(selected ? 1 : 0) }
                }
                .font(.body.weight(.bold))
                .foregroundStyle(focused ? Color.black : selected || highlighted ? theme.accent : .white.opacity(0.8))
                .frame(width: 30)
                if let thumbnail { thumbnail }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(selected ? .semibold : .regular)).lineLimit(1).truncationMode(.middle)
                    if let detail, showsDetail {
                        Text(detail).font(.caption.weight(highlighted ? .bold : .medium))
                            .foregroundStyle(focused ? Color.black.opacity(0.6) : highlighted ? theme.accent : .white.opacity(0.55))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).font(.callout.weight(.semibold).monospacedDigit()).opacity(0.7).contentTransition(.numericText())
                }
            }
            .foregroundStyle(focused ? .black : .white)
            .padding(.horizontal, 18)
            .padding(.vertical, showsDetail ? 11 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(focused ? Color.white : selected ? Color.white.opacity(0.07) : .clear, in: .rect(cornerRadius: 18, style: .continuous))
            .shadowWhen(focused, color: .black.opacity(0.35), radius: 16, y: 6)
            .animation(.spring(duration: 0.22, bounce: 0.15), value: focused)
            .onChange(of: focused) { _, now in
                guard detailWhenFocused else { return }
                withAnimation(.spring(duration: 0.32, bounce: 0.12)) { expanded = now }
            }
        }
    }
}

/// About what's playing: the art, what it is, what happens (spoiler-safe),
/// who's in it, and what's next.
struct ItemAbout: View {
    let controller: PlayerController
    /// Its name over the overview (the split's panel already has it, by Close).
    var showsName = true
    /// What's next (or who's in it) beside it; the watch page has Up Next for that.
    var showsSide = true
    @Environment(AppModel.self) private var app

    private var tv: Bool { Platform.isTV }
    private var phone: Bool { Layout.device == .phone }
    private var small: Font { tv ? .caption : .footnote }

    var body: some View {
        let item = controller.item
        let art: CGFloat = tv ? 300 : 120
        let layout = phone ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
                           : AnyLayout(HStackLayout(alignment: .top, spacing: tv ? 32 : 18))
        layout {
            HStack(alignment: .top, spacing: tv ? 28 : 14) {
                // You're watching it: its own still, never hidden as a spoiler.
                let kind: ArtworkKind = item.kind == .episode ? .still : .backdrop
                Artwork(ArtworkSource.resolve(item, kind), kind: kind, width: art)
                    .frame(width: art, height: art * 9 / 16)
                    .clipShape(.rect(cornerRadius: tv ? 14 : 8))
                VStack(alignment: .leading, spacing: tv ? 4 : 2) {
                    Text(Self.facts(item)).font(small).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    if showsName {
                        Text(item.name ?? "").font(tv ? .callout.weight(.semibold) : .subheadline.weight(.semibold)).lineLimit(1)
                    }
                    if let overview = item.overview {                     // you're watching it: no spoiler
                        Text(overview).font(small).foregroundStyle(.white.opacity(0.85)).lineLimit(tv ? 2 : 4)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, tv ? 6 : 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showsSide, sleepStop != nil || controller.upNext != nil || Self.starring(item) != nil || Self.director(item) != nil {
                side(item)
                    .frame(width: phone || controller.upNext != nil && sleepStop == nil ? nil : (tv ? 400 : 240), alignment: .leading)
                    .frame(maxHeight: phone ? nil : .infinity, alignment: .topLeading)   // the divider runs the band's height
                    .padding(.leading, phone ? 0 : (tv ? 28 : 16))
                    .overlay(alignment: .leading) {
                        if !phone { Rectangle().fill(.white.opacity(0.14)).frame(width: 1) }
                    }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.white)
    }

    /// What comes after this one — unless the sleep timer stops it first —
    /// or, with nothing after it, who's in it.
    @ViewBuilder private func side(_ item: BaseItem) -> some View {
        if let stop = sleepStop {
            HStack(alignment: .top, spacing: tv ? 14 : 8) {
                Image(systemName: "moon.zzz").font(small.weight(.semibold))
                lines("Sleep Timer", stop, nil)
            }
        } else if let next = controller.upNext {
            // A card the size of the art on the left: the next one's picture
            // (the show's art for an unwatched episode, so no spoiler), its
            // name over the foot of it.
            let words = Self.nextLines(next, after: item)
            let width: CGFloat = tv ? 300 : (phone ? 200 : 160)
            Artwork(item: next, kind: .landscape, width: width)
                .frame(width: width, height: width * 9 / 16)
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Up Next").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                        Text(words.title).font(small.weight(.semibold)).lineLimit(2)
                        if let detail = words.detail { Text(detail).font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(1) }
                    }
                    .padding(tv ? 14 : 8)
                }
                .clipShape(.rect(cornerRadius: tv ? 14 : 8))
        } else if let starring = Self.starring(item) {
            lines("Starring", starring, Self.director(item).map { "Directed by \($0)" })
        } else if let director = Self.director(item) {
            lines("Directed by", director, nil)
        }
    }

    private func lines(_ label: String, _ title: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(small).foregroundStyle(.white.opacity(0.6))
            Text(title).font(small.weight(.semibold)).lineLimit(2)
            if let detail { Text(detail).font(small).foregroundStyle(.white.opacity(0.6)).lineLimit(1) }
        }
    }

    /// "Stops after this episode", or "Stops in 18 min" when that comes
    /// before this one ends and the next would start.
    private var sleepStop: String? {
        let timer = app.sleepTimer
        switch timer.mode {
        case .off:
            return nil
        case .endOfItem:
            return "Stops after this \(controller.item.kind == .episode ? "episode" : controller.item.kind == .movie ? "film" : "one")"
        case .minutes:
            guard let left = timer.remaining else { return nil }
            if controller.upNext != nil, let engine = controller.engine, let length = engine.duration,
               left > length - engine.currentTime { return nil }
            return "Stops in \(max(1, Int((left.components.seconds + 59) / 60))) min"
        }
    }

    /// "The Fresh Prince of Bel-Air · S1 · E1 · 23 min · TV-PG";
    /// "1999 · 2 hr 16 min · R · Sci-Fi, Action".
    static func facts(_ item: BaseItem) -> String {
        let episode = item.kind == .episode
        var parts: [String] = []
        if episode, let series = item.seriesName { parts.append(series) }
        if let label = item.episodeLabel { parts.append(label) }
        if !episode, let year = item.productionYear { parts.append(String(year)) }
        if let runtime = item.runtime { parts.append(MetadataLine.runtimeString(runtime)) }
        if let rating = item.officialRating, !rating.isEmpty { parts.append(rating) }
        if !episode, let genres = item.genres, !genres.isEmpty { parts.append(genres.prefix(2).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    /// "E2 · Bang the Drum, Ashley" (same season), "S2 · E1 · …" (next
    /// season), a show's name under another show's episode; "Film · 2003".
    static func nextLines(_ next: BaseItem, after item: BaseItem) -> (title: String, detail: String?) {
        let name = next.name ?? ""
        switch next.kind {
        case .episode:
            let sameShow = next.seriesId != nil && next.seriesId == item.seriesId
            let label = sameShow && next.parentIndexNumber == item.parentIndexNumber ? next.indexNumber.map { "E\($0)" } : next.episodeLabel
            return ([label, name].compactMap { $0 }.joined(separator: " · "), sameShow ? nil : next.seriesName)
        case .movie:
            return (name, ["Film", next.productionYear.map(String.init)].compactMap { $0 }.joined(separator: " · "))
        default:
            return (name, next.productionYear.map(String.init))
        }
    }

    /// "Ralph Fiennes, Tony Revolori and Saoirse Ronan"
    static func starring(_ item: BaseItem) -> String? {
        let actors = (item.people ?? []).filter { $0.type == "Actor" }.prefix(3).compactMap(\.name)
        guard let last = actors.last else { return nil }
        return actors.count > 1 ? actors.dropLast().joined(separator: ", ") + " and " + last : last
    }

    static func director(_ item: BaseItem) -> String? {
        (item.people ?? []).first { $0.type == "Director" }?.name
    }
}
