#if !os(tvOS)
import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import PlaybackCore
import SwiftUI

/// The player off the TV (iPhone, iPad, Mac): the system player's shape.
/// Close and the title at the top; back and forward 10 s and play/pause in
/// the middle; the timeline at the bottom with Audio & Subtitles and More
/// (Info, Up Next, Playback) beside it — the TV's Up and Down. Glass over the
/// picture, the system's own menus and sheets — the TV's focus-driven
/// panels are for a remote.
struct TouchControls: View {
    @Environment(AppModel.self) private var app
    let controller: PlayerController
    let engine: any PlayerEngine
    let close: () -> Void
    /// Any touch keeps the controls up a while longer.
    let poke: () -> Void
    @Environment(\.verticalSizeClass) private var vertical
    /// Owned by the player, so they stay up when the controls hide.
    @Binding var findingSubtitles: Bool
    @Binding var showsMore: Bool
    /// Where they go: over the whole picture, over the split's picture (no
    /// menus row: it's in the panel below), or that row alone, in the panel.
    var style: Style = .full
    /// Switches between the picture full screen and the split.
    var split: (() -> Void)? = nil
    /// The split here goes side by side (a wide space): the button says so.
    var splitsBeside = false

    enum Style { case full, overPicture, menus }

    /// The split's (either part): Full Screen goes back, and More is right there below.
    private var docked: Bool { style != .full }
    private var playing: Bool { engine.status != .paused }
    private var phone: Bool { Layout.device == .phone }
    /// A phone on its side, or the split's band of picture: little height, so smaller and closer.
    private var short: Bool { vertical == .compact || style == .overPicture }

    var body: some View {
        Group {
            switch style {
            case .full, .overPicture:
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    transport
                    Spacer(minLength: 0)
                    if style == .full { bottom } else { timeline }
                }
            case .menus:
                menuRow
            }
        }
        .padding(.horizontal, phone ? 16 : 28)
        .padding(.top, style == .menus ? 14 : short ? 8 : 4)
        .padding(.bottom, style == .menus ? 0 : short ? 6 : phone ? 4 : 20)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)                      // glass and menus, dark over the picture
    }

    // MARK: Top

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            glassButton("xmark", "Close", size: 17) { close() }
                .accessibilityIdentifier("player.close")
            VStack(alignment: .leading, spacing: 1) {
                if let kicker { Text(kicker).font(.labelText.weight(.semibold)).foregroundStyle(.white.opacity(0.7)).lineLimit(1) }
                Text(controller.item.name ?? "").font(phone ? .headline : .title3.weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let split {
                glassButton(docked ? "arrow.up.left.and.arrow.down.right" : (splitsBeside ? "rectangle.split.2x1" : "rectangle.split.1x2"),
                            docked ? "Full Screen" : (splitsBeside ? "Show Details Beside" : "Show Details Below"), size: 15) { split() }
                    .accessibilityIdentifier("player.layout")
            }
            // Settings → Speakers Button: the system's speaker picker, a press away.
            if app.settings.speakersButton {
                SpeakerPickerButton(size: 24)                    // the system's own button, in a glass circle like the rest
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            // Only where this item's player can float its picture here.
            if let pip = engine.pictureInPicture, pip.isPossible || pip.isActive {
                glassButton(pip.isActive ? "pip.exit" : "pip.enter", pip.isActive ? "Exit Picture in Picture" : "Picture in Picture", size: 15) {
                    controller.togglePictureInPicture()
                }
                .accessibilityIdentifier("player.pip")
            }
            if controller.isBackground {
                Label("Untracked", systemImage: "infinity")
                    .font(.labelText.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.85), in: .capsule)
                    .accessibilityIdentifier("player.backgroundTag")
            }
        }
    }

    private var kicker: String? {
        let item = controller.item
        guard let series = item.seriesName else { return nil }
        if let s = item.parentIndexNumber, let e = item.indexNumber { return "\(series) · S\(s), E\(e)" }
        return series
    }

    // MARK: Middle

    private var transport: some View {
        let small: CGFloat = short ? 22 : phone ? 26 : 30
        return HStack(spacing: short ? 56 : phone ? 40 : 64) {
            glassButton("gobackward.10", "Back 10 seconds", size: small) { Task { await controller.skip(by: .seconds(-10)) } }
            glassButton(playing ? "pause.fill" : "play.fill", playing ? "Pause" : "Play", size: small * 1.45) { controller.togglePlayPause() }
                .accessibilityIdentifier("player.playPause")
            glassButton("goforward.10", "Forward 10 seconds", size: small) { Task { await controller.skip(by: .seconds(10)) } }
                .accessibilityIdentifier("player.forward")
        }
    }

    // MARK: Bottom

    private var bottom: some View {
        VStack(alignment: .leading, spacing: short ? 4 : 8) {
            timeline
            menuRow
        }
    }

    private var timeline: some View {
        Timeline(time: controller.displayTime, duration: engine.duration ?? controller.item.runtime ?? .zero,
                 scrubTime: nil, scrubThumb: nil, paused: engine.status == .paused,
                 seek: { t in Task { await controller.seek(to: t) }; poke() })
    }

    private var menuRow: some View {
        HStack(spacing: 10) {
            Text(facts)
                .font(.labelText.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            languagesMenu
            if !docked {
                // Docked, More is the panel below.
                HStack(spacing: 6) {
                    glassButton(controller.isBackground || app.sleepTimer.isActive ? "ellipsis.circle.fill" : "ellipsis.circle", "More", size: 15) { showsMore = true }
                    if let left = app.sleepTimer.shortLabel, !phone || !short {
                        Text(left).font(.labelText.weight(.semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.85))
                    }
                }
                .accessibilityIdentifier("control.more")
            }
        }
    }

    /// "Ends at 10:42 PM" (Background goes on: no end).
    private var facts: String {
        guard !controller.isBackground, let total = engine.duration ?? controller.item.runtime, total >= .seconds(60) else { return "" }
        let left = max(.zero, total - controller.displayTime)
        let end = Date.now.addingTimeInterval(left.seconds / Double(max(0.1, engine.rate)))
        return "Ends at " + end.formatted(date: .omitted, time: .shortened)
    }

    /// Audio & Subtitles: the TV's Up — the subtitles, Find Subtitles, and
    /// the audio, in one menu.
    private var languagesMenu: some View {
        Menu {
            Picker("Subtitles", selection: Binding(get: { controller.foundSubtitle == nil ? controller.selectedSubtitle : -2 },
                                                   set: { index in if index != -2 { Task { await controller.selectSubtitle(index) } } })) {
                Text("Off").tag(Int?.none)
                ForEach(controller.subtitleOptions, id: \.index) { stream in
                    Text(stream.displayTitle ?? stream.language ?? "Track \(stream.index)").tag(Int?.some(stream.index))
                }
                if let found = controller.foundSubtitle {
                    Text("\(found.name) (found)").tag(Int?.some(-2))
                }
            }
            .pickerStyle(.inline)
            Button("Find Subtitles…", systemImage: "magnifyingglass") {
                findingSubtitles = true
                Task { await controller.findSubtitles() }
            }
            if !controller.audioOptions.isEmpty {
                Picker("Audio", selection: Binding(get: { controller.engine?.selectedAudioTrack }, set: { id in if let id { Task { await controller.selectAudio(id) } } })) {
                    ForEach(controller.audioOptions) { track in
                        Text([track.title, track.detail ?? track.codec?.uppercased()].compactMap { $0 }.joined(separator: " · ")).tag(Int?.some(track.id))
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            glassFace(controller.selectedSubtitle != nil || controller.foundSubtitle != nil ? "captions.bubble.fill" : "captions.bubble", size: 15)
        }
        .bareMenu()
        .accessibilityLabel("Audio & Subtitles")
        .accessibilityIdentifier("control.languages")
        .simultaneousGesture(TapGesture().onEnded { poke() })
    }

    // MARK: Pieces

    private func glassButton(_ symbol: String, _ label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            action()
            poke()
        } label: {
            glassFace(symbol, size: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// An icon in a glass circle (tinted while `on`), big enough to hit.
    /// On (subtitles, Background, a sleep timer) shows as the filled glyph
    /// alone, as on the TV: a lit button read as a selected one.
    private func glassFace(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .contentTransition(.symbolEffect(.replace))
            .foregroundStyle(.white)
            .frame(width: max(40, size * 2.4), height: max(40, size * 2.4))
            .glassEffect(.regular.interactive(), in: .circle)
            .contentShape(.circle)
    }
}

/// "Find Subtitles…": the server searching, then what it found, best first.
struct FindSubtitlesSheet: View {
    let controller: PlayerController
    let done: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch controller.subtitleSearch {
                case .idle, .searching:
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Searching…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView("No Subtitles", systemImage: "captions.bubble", description: Text(message))
                case .results(let found):
                    List(Array(found.enumerated()), id: \.element.id) { i, sub in
                        Button {
                            Task { await controller.use(sub) }
                            done()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sub.name).lineLimit(2)
                                    Text(FoundSubtitles.detail(sub, best: i == 0)).font(.labelText.weight(i == 0 && FoundSubtitles.isClearFit(sub) ? .bold : .regular))
                                        .foregroundStyle(i == 0 && FoundSubtitles.isClearFit(sub) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                }
                                Spacer()
                                if controller.foundSubtitle?.id == sub.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .accessibilityIdentifier("option.found-\(sub.id)")
                    }
                }
            }
            .navigationTitle("Find Subtitles")
            .navigationBarTitleDisplayModeInline()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: done) } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

/// More, full screen: Info, Up Next and Playback in a sheet (the split has
/// them in its panel).
struct MoreSheet: View {
    let controller: PlayerController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WatchPanelContent(controller: controller, showsHeader: false, opensOn: .info)
                .navigationTitle(controller.item.name ?? "")
                .navigationBarTitleDisplayModeInline()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

private extension View {
    @ViewBuilder func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
#endif
