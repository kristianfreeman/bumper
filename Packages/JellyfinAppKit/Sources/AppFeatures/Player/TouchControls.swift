#if !os(tvOS)
import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import PlaybackCore
import SwiftUI

/// The player off the TV (iPhone, iPad, Mac): the system player's shape.
/// Close and the title at the top; back, play/pause and forward in the
/// middle; the timeline at the bottom with the subtitle and audio menus,
/// Background and Info beside it. Glass over the picture, the system's
/// own menus and sheets — the TV's focus-driven cards are for a remote.
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
    @Binding var showsInfo: Bool

    private var playing: Bool { engine.status != .paused }
    private var phone: Bool { Layout.device == .phone }
    /// A phone on its side: little height, so smaller and closer.
    private var short: Bool { vertical == .compact }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            transport
            Spacer(minLength: 0)
            bottom
        }
        .padding(.horizontal, phone ? 16 : 28)
        .padding(.top, short ? 8 : 4)
        .padding(.bottom, short ? 6 : phone ? 4 : 20)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)                      // glass and menus, dark over the picture
    }

    // MARK: Top

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            glassButton("xmark", "Close", size: 17) { close() }
                .accessibilityIdentifier("player.close")
            VStack(alignment: .leading, spacing: 1) {
                if let kicker { Text(kicker).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7)).lineLimit(1) }
                Text(controller.item.name ?? "").font(phone ? .headline : .title3.weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if controller.isBackground {
                Label("Background", systemImage: "infinity")
                    .font(.caption.weight(.semibold))
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
            glassButton("goforward.30", "Forward 30 seconds", size: small) { Task { await controller.skip(by: .seconds(30)) } }
        }
    }

    // MARK: Bottom

    private var bottom: some View {
        VStack(alignment: .leading, spacing: short ? 4 : 8) {
            Timeline(time: controller.displayTime, duration: engine.duration ?? controller.item.runtime ?? .zero,
                     scrubTime: nil, scrubThumb: nil, paused: engine.status == .paused,
                     seek: { t in Task { await controller.seek(to: t) }; poke() })
            HStack(spacing: 10) {
                Text(facts)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                subtitlesMenu
                audioMenu
                playbackMenu
                glassButton("info.circle", "Info", size: 15) { showsInfo = true }
                    .accessibilityIdentifier("control.info")
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

    private var subtitlesMenu: some View {
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
            Divider()
            Button("Find Subtitles…", systemImage: "magnifyingglass") {
                findingSubtitles = true
                Task { await controller.findSubtitles() }
            }
        } label: {
            glassFace(controller.selectedSubtitle != nil || controller.foundSubtitle != nil ? "captions.bubble.fill" : "captions.bubble", size: 15,
                      on: controller.selectedSubtitle != nil || controller.foundSubtitle != nil)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Subtitles")
        .accessibilityIdentifier("control.subtitles")
        .simultaneousGesture(TapGesture().onEnded { poke() })
    }

    private var audioMenu: some View {
        Menu {
            Picker("Audio", selection: Binding(get: { controller.engine?.selectedAudioTrack }, set: { id in if let id { Task { await controller.selectAudio(id) } } })) {
                ForEach(controller.audioOptions) { track in
                    Text([track.title, track.detail ?? track.codec?.uppercased()].compactMap { $0 }.joined(separator: " · ")).tag(Int?.some(track.id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            glassFace("speaker.wave.2", size: 15)
        }
        .menuIndicator(.hidden)
        .disabled(controller.audioOptions.count < 2)
        .accessibilityLabel("Audio")
        .accessibilityIdentifier("control.audio")
        .simultaneousGesture(TapGesture().onEnded { poke() })
    }

    /// Playback: Background, and the sleep timer (only here, by what's
    /// playing). Lit while either is on, with the time left.
    private var playbackMenu: some View {
        let timer = app.sleepTimer
        let on = timer.isActive || controller.isBackground
        return Menu {
            Toggle(isOn: Binding(get: { controller.isBackground }, set: { controller.setBackground($0) })) {
                Label("Background", systemImage: "infinity")
            }
            Picker("Sleep Timer", selection: Binding(get: { timer.mode }, set: { mode in
                if mode == .off { timer.reset() } else { timer.set(mode) }
            })) {
                Text("Off").tag(SleepTimer.Mode.off)
                ForEach(SleepTimer.presets, id: \.self) { m in Text(SleepTimer.title(m)).tag(SleepTimer.Mode.minutes(m)) }
                Text(controller.item.kind == .episode ? "End of This Episode" : "End of This Film").tag(SleepTimer.Mode.endOfItem)
            }
            .pickerStyle(.menu)
        } label: {
            HStack(spacing: 6) {
                glassFace(on ? "gearshape.fill" : "gearshape", size: 15, on: on)
                if let left = timer.shortLabel, !phone || !short {
                    Text(left).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Playback")
        .accessibilityIdentifier("control.playback")
        .simultaneousGesture(TapGesture().onEnded { poke() })
    }

    // MARK: Pieces

    private func glassButton(_ symbol: String, _ label: String, size: CGFloat, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            action()
            poke()
        } label: {
            glassFace(symbol, size: size, on: on)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// An icon in a glass circle (tinted while `on`), big enough to hit.
    private func glassFace(_ symbol: String, size: CGFloat, on: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .contentTransition(.symbolEffect(.replace))
            .foregroundStyle(on ? Color.black : .white)
            .frame(width: max(40, size * 2.4), height: max(40, size * 2.4))
            .background(on ? Color.white : .clear, in: .circle)
            .glassEffect(on ? .identity : .regular.interactive(), in: .circle)
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
                                    Text(FoundSubtitles.detail(sub, best: i == 0)).font(.caption.weight(i == 0 && FoundSubtitles.isClearFit(sub) ? .bold : .regular))
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

/// Which player, which decoder, and why.
struct InfoSheet: View {
    let controller: PlayerController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView { ItemAbout(controller: controller).padding(16) }
                .navigationTitle(controller.item.kind == .episode ? "About This Episode" : "About This Film")
                .navigationBarTitleDisplayModeInline()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
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
