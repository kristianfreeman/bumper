import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import PlaybackCore
import SwiftUI

/// The three menus the icon row above the timeline opens.
enum PlayerMenu: String, CaseIterable, Hashable {
    case subtitles, audio, info

    var symbol: String {
        switch self {
        case .subtitles: "captions.bubble"
        case .audio: "speaker.wave.2"
        case .info: "info.circle"
        }
    }

    var title: String {
        switch self {
        case .subtitles: "Subtitles"
        case .audio: "Audio"
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
                Image(systemName: flash.symbol)
                    .font(.system(size: flash.edge == .center ? 64 : 48, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 150, height: 150)
                    .background(Color.black.opacity(0.55), in: .circle)
                    .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 2))
                    .frame(maxWidth: .infinity, alignment: alignment(flash.edge))
                    .padding(.horizontal, 220)
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

/// Bottom controls: title, the icon row, then the timeline (with the scrub
/// preview riding above its head while paused).
struct TransportBar: View {
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
            // Beside each other on the TV, Mac and iPad; stacked on a phone.
            let layout = Layout.device == .phone ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18)) : AnyLayout(HStackLayout(alignment: .bottom, spacing: 40))
            layout {
                VStack(alignment: .leading, spacing: 8) {
                    if let kicker {
                        Text(kicker).font(.callout.weight(.semibold)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                    Text(controller.item.name ?? "")
                        .font(.system(size: Platform.isTV ? 52 : Layout.pageTitleSmall, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !facts.isEmpty {
                        HStack(spacing: 14) {
                            ForEach(Array(facts.enumerated()), id: \.offset) { i, fact in
                                if i > 0 { Circle().fill(.white.opacity(0.5)).frame(width: 5, height: 5) }
                                if fact.boxed { Badge(fact.text) } else { Text(fact.text) }
                            }
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    }
                }
                if Layout.device != .phone { Spacer(minLength: 0) }
                HStack(spacing: 22) {
                    ForEach(PlayerMenu.allCases, id: \.self) { menu in
                        Pill(menu.title, systemImage: menu.symbol + (openMenu == menu || badge(for: menu) ? ".fill" : ""), active: badge(for: menu)) { open(menu) }
                            .accessibilityIdentifier("control.\(menu.rawValue)")
                            .focused(focus, equals: .control(menu))
                            .tvMoveCommand { if $0 == .down { leave() } }
                    }
                }
                .tvFocusSection()
            }
            .padding(.bottom, 50)
            .opacity(scrubTime == nil ? 1 : 0)              // the preview takes this space
            .animation(.easeOut(duration: 0.15), value: scrubTime == nil)
            Timeline(time: controller.displayTime, duration: engine.duration ?? controller.item.runtime ?? .zero,
                     scrubTime: scrubTime, scrubThumb: scrubThumb, paused: engine.status == .paused,
                     seek: { t in Task { await controller.seek(to: t) } })
        }
        .padding(.horizontal, Platform.isTV ? 90 : Layout.horizontalMargin + 8)
        .padding(.top, Platform.isTV ? 60 : 24)
        .padding(.bottom, Platform.isTV ? 64 : 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(engine.status == .paused ? "transport.paused" : "transport.playing")
    }

    private struct Fact { let text: String; var boxed = false }

    /// "2012 · PG-13 · 2 h 44 min · Ends at 10:42 PM · 4K · HDR10"
    private var facts: [Fact] {
        let item = controller.item
        var out: [Fact] = []
        if controller.isBackground { out.append(Fact(text: "Background · not marking watched", boxed: true)) }
        if item.seriesName == nil, let year = item.productionYear { out.append(Fact(text: String(year))) }
        if let rating = item.officialRating, !rating.isEmpty { out.append(Fact(text: rating, boxed: true)) }
        let total = engine.duration ?? item.runtime
        if let total, total >= .seconds(60) {
            let left = max(.zero, total - controller.displayTime)
            out.append(Fact(text: Self.length(total)))
            let end = Date.now.addingTimeInterval(left.seconds / Double(max(0.1, engine.rate)))
            out.append(Fact(text: "Ends at " + end.formatted(date: .omitted, time: .shortened)))
        }
        if let f = engine.videoFormat {
            out.append(Fact(text: f.height >= 2000 ? "4K" : f.height >= 700 ? "HD" : "SD", boxed: true))
            if f.dynamicRange != .sdr { out.append(Fact(text: f.dynamicRange.rawValue, boxed: true)) }
        }
        return out
    }

    private static func length(_ d: Duration) -> String {
        let minutes = Int(d.seconds / 60)
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    private var kicker: String? {
        let item = controller.item
        guard let series = item.seriesName else { return nil }
        if let s = item.parentIndexNumber, let e = item.indexNumber { return "\(series) · Season \(s), Episode \(e)" }
        return series
    }

    private func badge(for menu: PlayerMenu) -> Bool {
        switch menu {
        case .subtitles: controller.selectedSubtitle != nil
        default: false
        }
    }
}

private struct Badge: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.5), lineWidth: 2))
    }
}

/// Progress, times, and — while scrubbing — a frame preview above the head.
private struct Timeline: View {
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

/// "Find Subtitles": searching, then what was found — best fit first, with
/// how sure we are and why.
private struct FoundSubtitles: View {
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
                Text("Looking for subtitles that fit this file…").foregroundStyle(.white.opacity(0.75))
            }
            .padding(20)
            .focusable()
            .focused(focus, equals: .option("sub-searching"))
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message).foregroundStyle(.white.opacity(0.75)).padding(.horizontal, 20).padding(.bottom, 8)
                OptionRow(title: "Back", detail: nil, selected: false, id: "sub-back", focus: focus) { controller.subtitleSearch = .idle }
            }
        case .results(let found):
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(found.enumerated()), id: \.element.id) { i, sub in
                        OptionRow(title: sub.name,
                                  detail: Self.detail(sub, best: i == 0), selected: controller.foundSubtitle?.id == sub.id,
                                  id: "found-\(sub.id)", focus: focus) {
                            Task { await controller.use(sub) }
                            close()
                        }
                    }
                    OptionRow(title: "Back", detail: nil, selected: false, id: "sub-back", focus: focus) { controller.subtitleSearch = .idle }
                }
                .padding(.horizontal, 8)
            }
            .scrollClipDisabled()
            .frame(maxHeight: 560)
        }
    }

    /// "Best match · 94% · Same release group (SPARKS)"
    static func detail(_ sub: FoundSubtitle, best: Bool) -> String {
        ([best ? "Best match" : nil, sub.confidenceText, sub.reasons.first, sub.remote.hearingImpaired == true ? "SDH" : nil] as [String?])
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// The card a chrome icon opens, anchored above the icon row on the right.
struct MenuCard: View {
    let menu: PlayerMenu
    let controller: PlayerController
    var focus: FocusState<PlayerView.PlayerFocus?>.Binding
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(menu.title, systemImage: menu.symbol)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 20)
            content
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
        .frame(width: menu == .info ? 820 : 620, alignment: .leading)
        .overVideoPanel(cornerRadius: 32)
        .tvFocusSection()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 90)
        .padding(.bottom, 290)
        .defaultFocus(focus, defaultOption)
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

    @ViewBuilder
    private var content: some View {
        switch menu {
        case .subtitles:
            if controller.subtitleSearch == .idle {
                ScrollView {
                    VStack(spacing: 4) {
                        OptionRow(title: "Off", detail: nil, selected: controller.selectedSubtitle == nil && controller.foundSubtitle == nil, id: "sub-off", focus: focus) {
                            Task { await controller.selectSubtitle(nil) }
                            close()
                        }
                        ForEach(controller.subtitleOptions, id: \.index) { stream in
                            OptionRow(title: stream.displayTitle ?? stream.language ?? "Track \(stream.index)",
                                      detail: stream.codec?.uppercased(), selected: controller.selectedSubtitle == stream.index,
                                      id: "sub-\(stream.index)", focus: focus) {
                                Task { await controller.selectSubtitle(stream.index) }
                                close()
                            }
                        }
                        if let found = controller.foundSubtitle {
                            OptionRow(title: found.name, detail: "Found · \(found.confidenceText)", selected: true, id: "sub-found", focus: focus) { close() }
                        }
                        OptionRow(title: "Find Subtitles…", detail: "Your server searches; the best fit comes first", selected: false, id: "sub-find", focus: focus) {
                            Task { await controller.findSubtitles() }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .scrollClipDisabled()
                .frame(maxHeight: min(560, CGFloat(controller.subtitleOptions.count + 2 + (controller.foundSubtitle == nil ? 0 : 1)) * 76))
            } else {
                FoundSubtitles(controller: controller, focus: focus, close: close)
            }
        case .audio:
            VStack(spacing: 4) {
                ForEach(controller.audioOptions) { track in
                    OptionRow(title: track.title, detail: track.detail ?? track.codec?.uppercased(),
                              selected: controller.engine?.selectedAudioTrack == track.id, id: "audio-\(track.id)", focus: focus) {
                        Task { await controller.selectAudio(track.id) }
                        close()
                    }
                }
            }
        case .info:
            InfoContent(controller: controller)
                .focusable()
                .focused(focus, equals: .option("info"))
        }
    }

    private func isOption(_ f: PlayerView.PlayerFocus?) -> Bool {
        if case .option = f { true } else { false }
    }

    private var defaultOption: PlayerView.PlayerFocus {
        switch menu {
        case .subtitles:
            switch controller.subtitleSearch {
            case .results(let found): .option(found.first.map { "found-\($0.id)" } ?? "sub-back")
            case .searching: .option("sub-searching")
            case .failed: .option("sub-back")
            case .idle: .option(controller.foundSubtitle != nil ? "sub-found" : controller.selectedSubtitle.map { "sub-\($0)" } ?? "sub-off")
            }
        case .audio: .option((controller.engine?.selectedAudioTrack ?? controller.audioOptions.first?.id).map { "audio-\($0)" } ?? "audio-none")
        case .info: .option("info")
        }
    }
}

private struct OptionRow: View {
    let title: String
    let detail: String?
    let selected: Bool
    let id: String
    var focus: FocusState<PlayerView.PlayerFocus?>.Binding
    let action: () -> Void

    var body: some View {
        Button(action: action) { Face(title: title, detail: detail, selected: selected) }
            .buttonStyle(BareButtonStyle())
            .focused(focus, equals: .option(id))
            .accessibilityIdentifier("option.\(id)")
    }

    private struct Face: View {
        let title: String
        let detail: String?
        let selected: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            HStack(spacing: 16) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .opacity(selected ? 1 : 0)
                    .frame(width: 30)
                Text(title).font(.body.weight(selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 12)
                if let detail { Text(detail).font(.caption.weight(.semibold)).opacity(0.6) }
            }
            .foregroundStyle(focused ? .black : .white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(focused ? Color.white : .clear, in: .rect(cornerRadius: 16))
            .scaleEffect(focused ? 1.03 : 1)
            .animation(.spring(duration: 0.18), value: focused)
        }
    }
}

private struct InfoContent: View {
    let controller: PlayerController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let engine = controller.engine {
                row("Player", engine.kind == .vlc ? "VLCKit" : "AVPlayer")
                if let f = engine.videoFormat {
                    row("Video", "\(f.codec.uppercased()) · \(f.width)×\(f.height) · \(f.frameRate.formatted(.number.precision(.fractionLength(0...3)))) fps")
                    row("Range", "\(f.dynamicRange.rawValue) · \(f.bitDepth)-bit · \(f.hardwareDecoded ? "hardware" : "software") decode")
                }
                row("Audio", engine.stats.audio)
                row("Method", engine.stats.method)
                if let bitrate = controller.plan?.mediaSource.bitrate, bitrate > 0 {
                    row("Bitrate", Self.mbps(Double(bitrate) / 1e6))
                } else if let mbps = engine.stats.bitrateMbps, mbps > 0 {
                    row("Bitrate", Self.mbps(mbps))
                }
            }
            if let reasons = controller.plan?.reasons, !reasons.isEmpty {
                Text(reasons.joined(separator: "\n")).font(.caption).foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 20)
        .foregroundStyle(.white)
    }

    private static func mbps(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) Mb/s"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.callout.weight(.semibold)).foregroundStyle(.white.opacity(0.6)).frame(width: 140, alignment: .leading)
            Text(value).font(.callout).lineLimit(2)
        }
    }
}
