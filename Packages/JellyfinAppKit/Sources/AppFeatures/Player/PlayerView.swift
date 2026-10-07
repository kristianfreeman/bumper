import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import os
import PlaybackCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Full-screen player — one UI for both backends. The remote's behaviour
/// lives in `TransportModel` (see its table); this view draws it and routes
/// the remote to it through `RemoteGestures`.
struct PlayerView: View {
    let request: PlaybackRequest
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var controller: PlayerController?
    @State private var chromeVisible = true
    @State private var openMenu: PlayerMenu?
    @State private var scrubThumb: CGImage?
    @State private var flash: Flash?
    @State private var hideTask: Task<Void, Never>?
    @State private var thumbTask: Task<Void, Never>?
    /// Pinched out: the picture fills the screen (iPhone, iPad).
    @State private var fills = false
    /// Off the TV: the Find Subtitles and Info sheets.
    @State private var findingSubtitles = false
    @State private var showsInfo = false
    /// The picture full screen (false) or over the controls (true) by
    /// choice; nil goes by the space's shape. A new shape clears it.
    @State private var splitChoice: Bool?
    /// Split: Find Subtitles opens below the picture, not in a sheet.
    @State private var docked = false
    @FocusState private var focus: PlayerFocus?
    /// Focus is on the icon row: the video isn't a place to move to (Left
    /// from the first icon went onto it, invisibly). Down goes back.
    @State private var onControls = false

    enum PlayerFocus: Hashable { case surface, skip, control(PlayerMenu), option(String) }

    var body: some View {
        // Two halves for the type checker (one long chain was too much on
        // macOS). Called on self: a modifier holding a copy of the view saw
        // copies of its state, and playback never started.
        lifecycle(layers)
    }

    @ViewBuilder
    private var layers: some View {
        #if os(tvOS)
        layers(PlayerSplit.full)
        #else
        // Room for more than the picture (a phone or iPad upright, a tall Mac
        // window, iPhone Duo folded on a table): the picture on top, the
        // controls and what's around it below. One tree either way, so the
        // video view is never rehosted.
        GeometryReader { proxy in
            let byShape = PlayerSplit.splits(proxy.size, fold: PlayerSplit.fold(in: proxy))
            let layout = (splitChoice ?? byShape)
                ? PlayerSplit(size: proxy.size, fold: PlayerSplit.fold(in: proxy), aspect: controller?.videoAspect)
                : PlayerSplit.full
            layers(layout)
                .onChange(of: byShape) { _, _ in splitChoice = nil }      // a new shape: its own way again
                .onChange(of: layout.isSplit, initial: true) { _, split in docked = split }
        }
        #endif
    }

    private func layers(_ split: PlayerSplit) -> some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if let engine = controller?.engine {
                VideoSurface(view: engine.videoView)
                    .modifier(split.picture)
                if engine.pictureInPicture?.isActive == true {
                    // Floating, with the screen still here (you left the app and came back).
                    VStack(spacing: 10) {
                        Image(systemName: "pip").font(.system(size: 44, weight: .light))
                        Text("Playing in Picture in Picture").font(.callout)
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .modifier(split.picture)
                }
            }
            if let controller {
                SubtitleOverlay(cue: controller.currentCue, scale: app.settings.subtitleScale, style: app.settings.subtitleStyle, font: app.settings.subtitleFont,
                                raised: chromeVisible && !split.isSplit, videoAspect: controller.videoAspect, fullBleed: !split.isSplit)
                    .modifier(split.picture)
                Text(controller.subtitleStatus)                 // invisible; UI tests read it
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("player.subtitles")
                    .allowsHitTesting(false)
                // Position and scrub head in ms, for UI tests (invisible).
                Text(verbatim: String(Int(controller.displayTime.milliseconds)))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("player.time")
                    .allowsHitTesting(false)
                Text(verbatim: controller.transport.head.map { String(Int($0.milliseconds)) } ?? "none")
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("player.head")
                    .allowsHitTesting(false)
            }
            ChromeScrim()
                .opacity(!split.isSplit && (chromeVisible || openMenu != nil) ? 1 : 0)
            // The video's focus target (a sibling of the controls, so
            // left/right on an icon or menu row move focus, not the video).
            // Presses and swipes on it are read by RemoteGestures.
            Color.clear
                .contentShape(.rect)
                .focusable(openMenu == nil && !onControls)
                .focused($focus, equals: .surface)
                .modifier(split.picture)
                .accessibilityIdentifier("player.surface")
                #if !os(tvOS)
                // Tap / click the picture: the controls (or a menu) come and go.
                .onTapGesture {
                    if openMenu != nil { closeMenu() } else if chromeVisible { chromeVisible = false } else { showChrome() }
                }
                // Pinch out to fill the screen, in to see the whole picture.
                .simultaneousGesture(MagnifyGesture().onEnded { value in
                    if value.magnification > 1.08 { fills = true } else if value.magnification < 0.92 { fills = false }
                })
                #endif
            if let controller {
                RemoteGestures(transport: controller.transport, active: focus == .surface && openMenu == nil,
                               // Select with the controls down brings them up (playing on);
                               // with them up, it plays and pauses.
                               showsControls: { if chromeVisible { return false }; showChrome(); return true }) {
                    showChrome()
                    focus = .control(.subtitles)
                }
                .frame(width: 0, height: 0)
            }
            preparingOverlay
                .modifier(split.picture)                // split: loading in the picture, the controls already below
            #if os(tvOS)
            if chromeVisible, let controller, let engine = controller.engine {
                TransportBar(controller: controller, engine: engine, scrubTime: controller.transport.head, scrubThumb: scrubThumb,
                             openMenu: openMenu, focus: $focus, open: { open($0) }, leave: { backToVideo() })
                    .transition(.opacity)
            }
            #else
            if split.isSplit, let controller, let engine = controller.engine {
                // Below the picture (and the fold): always up, nothing over the video.
                PlayerPanel(controller: controller, engine: engine, close: { leavePlayer() }, poke: { showChrome() },
                            fullScreen: { splitChoice = false }, findingSubtitles: $findingSubtitles)
                    .padding(.top, split.panelTop)
            } else if chromeVisible, let controller, let engine = controller.engine {
                TouchControls(controller: controller, engine: engine, close: { leavePlayer() }, poke: { showChrome() },
                              findingSubtitles: $findingSubtitles, showsInfo: $showsInfo, split: { splitChoice = true })
                    .transition(.opacity)
            }
            #endif
            if let menu = openMenu, let controller {
                MenuCard(menu: menu, controller: controller, focus: $focus, close: { closeMenu() })
                    .id(menu)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
            }
            FlashView(flash: flash)
                .modifier(split.pictureArea)
            skipButton(docked: split.isSplit)
                .modifier(split.pictureArea)
            if app.showsPerformanceHUD, let engine = controller?.engine {
                EngineStatsView(stats: engine.stats, format: engine.videoFormat)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(40)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The player's modifiers, apart from its layers (one long chain was
    /// too much for the type checker on macOS).
    private func lifecycle<V: View>(_ content: V) -> some View {
        content
            .defaultFocus($focus, .surface)
            .tvExitCommand(perform: handleExit)
            #if !os(tvOS)
            // A keyboard (Mac, iPad): Space plays and pauses, arrows skip, Escape leaves.
            .focusable()
            .onKeyPress(.space) { controller?.togglePlayPause(); showChrome(); return .handled }
            .onKeyPress(.leftArrow) { Task { await controller?.skip(by: .seconds(-10)) }; showChrome(); return .handled }
            .onKeyPress(.rightArrow) { Task { await controller?.skip(by: .seconds(30)) }; showChrome(); return .handled }
            .onKeyPress(.escape) { handleExit(); return .handled }
            #endif
            .animation(.easeInOut(duration: 0.22), value: chromeVisible)
            .animation(.spring(duration: 0.28), value: openMenu)
            .task {
                // Back from Picture in Picture: the same playback, where it is.
                if let floating = app.floatingPlayer {
                    app.floatingPlayer = nil
                    if floating.request.id == request.id {
                        controller = floating
                        floating.transport.onActivity = { showChrome() }
                        scheduleHide()
                        return
                    }
                    await floating.stop()                  // something else to play: the floating one ends
                }
                let c = PlayerController(request: request, app: app)
                controller = c
                c.transport.onActivity = { showChrome() }
                await c.start()
                scheduleHide()
            }
            .onDisappear {
                // Closed for Picture in Picture: it plays on, held by the app.
                if let controller, app.floatingPlayer !== controller { Task { await controller.stop() } }
            }
            .onChange(of: fills) { _, fill in controller?.engine?.setFillsScreen(fill) }
            // A new engine (AVPlayer handing over to VLCKit) keeps the choice.
            .onChange(of: controller?.engine.map { ObjectIdentifier($0) }) { _, _ in controller?.engine?.setFillsScreen(fills) }
            .onChange(of: controller?.activeSegment?.id) { _, id in
                if id != nil { focus = .skip } else if focus == .skip { focus = .surface }
            }
            .onChange(of: focus) { _, now in focusChanged(now) }
            .onChange(of: controller?.transport.head) { _, head in updateThumbnail(for: head) }
            .onChange(of: controller?.transport.feedback) { _, feedback in
                guard let feedback else { return }
                show(Flash(feedback.kind))
            }
            .task(id: controller?.transport.scanning != nil) {
                // A held left/right: advance the head every frame.
                guard let transport = controller?.transport, transport.scanning != nil else { return }
                var last = ContinuousClock.now
                while !Task.isCancelled, transport.scanning != nil {
                    try? await Task.sleep(for: .milliseconds(16))
                    let now = ContinuousClock.now
                    transport.tick(last.duration(to: now))
                    last = now
                }
            }
            .hidesSystemOverlays()
            #if !os(tvOS)
            .sheet(isPresented: Binding(get: { findingSubtitles && !docked }, set: { findingSubtitles = $0 }),
                   onDismiss: { if !docked { controller?.subtitleSearch = .idle; showChrome() } }) {
                if let controller { FindSubtitlesSheet(controller: controller) { findingSubtitles = false } }
            }
            .sheet(isPresented: $showsInfo, onDismiss: { showChrome() }) {
                if let controller { InfoSheet(controller: controller) }
            }
            #endif
    }

    /// From the icon row back to the video: it becomes focusable again first.
    private func backToVideo() {
        onControls = false
        Task { @MainActor in
            for _ in 0..<5 where focus != .surface {
                await Task.yield()
                focus = .surface
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    /// Every move is activity: the controls stay up, and go again once
    /// they're left alone (`scheduleHide`).
    private func focusChanged(_ now: PlayerFocus?) {
        TraceFile.write("focus", now.map { "\($0)" } ?? "none")
        if case .control = now {
            onControls = true
            chromeVisible = true
        }
        scheduleHide()
    }

    // MARK: Pieces

    @ViewBuilder
    private var preparingOverlay: some View {
        switch controller?.phase {
        case .preparing, nil:
            ZStack {
                FocusBackdrop(request.item)
                VStack(spacing: 30) {
                    ProgressView().scaleEffect(1.6)
                    VStack(spacing: Platform.isTV ? 12 : 6) {
                        Text(request.item.name ?? "").font(.title3).foregroundStyle(theme.primaryText)
                        SlowStartNote(resumingAt: request.resumePoint)
                    }
                }
            }
            .transition(.opacity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Can't play this", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func skipButton(docked: Bool) -> some View {
        if let controller, let segment = controller.activeSegment {
            Button {
                Task { await controller.skip(segment) }
            } label: {
                Label(label(for: segment), systemImage: "forward.end.fill").font(.headline).padding(.horizontal, 12)
            }
            .focused($focus, equals: .skip)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.horizontal, Platform.isTV ? 90 : Layout.horizontalMargin + 8)
            .padding(.bottom, Platform.isTV ? (chromeVisible ? 300 : 90) : (chromeVisible && !docked ? SubtitleOverlay.controlsHeight : 16))
            .transition(.opacity)
        }
    }

    private func label(for segment: MediaSegment) -> String {
        switch segment.type {
        case .intro: "Skip Intro"
        case .recap: "Skip Recap"
        case .preview: "Skip Preview"
        case .commercial: "Skip Ad"
        case .outro: controller?.nextEpisode != nil ? "Next Episode" : "Skip Credits"
        case .unknown: "Skip"
        }
    }

    // MARK: Input

    private func open(_ menu: PlayerMenu) {
        openMenu = menu
        scheduleHide()
    }

    private func closeMenu() {
        let was = openMenu
        openMenu = nil
        if let was { focus = .control(was) }
    }

    /// Menu/Back: close a menu → cancel a scrub → leave the icons → hide the
    /// controls → leave the player.
    private func handleExit() {
        // Found subtitles → back to the list (not out of the card).
        if openMenu == .subtitles, let controller, controller.subtitleSearch != .idle { controller.subtitleSearch = .idle; return }
        if openMenu != nil { closeMenu(); return }
        if controller?.transport.cancel() == true { showChrome(); return }
        if case .control = focus { backToVideo(); return }
        if chromeVisible && controller?.isPlaying == true { chromeVisible = false; return }
        leavePlayer()
    }

    private func leavePlayer() {
        Task {
            await controller?.stop()
            app.playback = nil
        }
    }

    /// The thumbnail for the scrub head; a newer position supersedes it (the
    /// last image stays up meanwhile, so dragging never flashes empty).
    private func updateThumbnail(for head: Duration?) {
        thumbTask?.cancel()
        guard let head, let controller else { scrubThumb = nil; return }
        thumbTask = Task {
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            let image = await controller.scrubThumbnail(at: head)
            if !Task.isCancelled, let image { scrubThumb = image }
        }
    }

    // MARK: Chrome

    /// Another ±10 s on the same side while its badge is up: the same badge
    /// counts up (and bounces), held a little longer; anything else replaces it.
    private func show(_ f: Flash) {
        if let current = flash, current.symbol == f.symbol, f.edge != .center {
            flash?.count += 1
        } else {
            flash = f
        }
        guard let shown = flash else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(shown.count > 1 ? 900 : 650))
            if flash?.id == shown.id, flash?.count == shown.count { flash = nil }
        }
    }

    private func showChrome() {
        chromeVisible = true
        scheduleHide()
    }

    /// Left alone while it plays, the controls go: 4 s from the video, 8 s
    /// on the icons, 20 s in an open card (time to read it). Paused, they stay.
    private func scheduleHide() {
        hideTask?.cancel()
        let wait: Duration = openMenu != nil ? .seconds(20) : onControls ? .seconds(8) : .seconds(4)
        hideTask = Task {
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let controller, !controller.transport.isScrubbing, !findingSubtitles, !showsInfo, controller.isPlaying else { return }
            if openMenu == .subtitles, controller.subtitleSearch != .idle { return }      // searching: wait for it
            openMenu = nil
            if onControls { backToVideo() }
            chromeVisible = false
        }
    }
}

/// Under the title while it opens: nothing for a second, then where it's
/// going ("Getting to 42:10…"). Its line is always there, so the title
/// doesn't move when the words come.
private struct SlowStartNote: View {
    let resumingAt: Duration?
    @State private var waited: Duration = .zero
    @Environment(\.theme) private var theme

    var body: some View {
        let message = SlowStart.message(resumingAt: resumingAt, after: waited)
        Text(message ?? " ")
            .font(.callout.monospacedDigit())
            .foregroundStyle(theme.secondaryText)
            .opacity(message == nil ? 0 : 1)
            .accessibilityHidden(message == nil)
            .accessibilityIdentifier("player.startMessage")
            .task {
                try? await Task.sleep(for: SlowStart.delay)
                withAnimation(.easeOut(duration: 0.3)) { waited = SlowStart.delay }
            }
    }
}

/// Hosts the active backend's video view (AVPlayerLayer-backed, or
/// VLCKit's drawable). Swaps cleanly if the item moves to another backend.
#if canImport(UIKit)
struct VideoSurface: UIViewRepresentable {
    let view: UIView

    final class HostView: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            hosted?.frame = bounds          // VLCKit sizes its output from the drawable's frame
        }

        var hosted: UIView? {
            didSet {
                guard hosted !== oldValue else { return }
                oldValue?.removeFromSuperview()
                if let hosted {
                    hosted.frame = bounds
                    hosted.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    addSubview(hosted)
                }
            }
        }
    }

    func makeUIView(context: Context) -> HostView {
        let host = HostView()
        host.backgroundColor = .black
        host.hosted = view
        return host
    }

    func updateUIView(_ host: HostView, context: Context) {
        host.hosted = view
    }
}
#else
struct VideoSurface: NSViewRepresentable {
    let view: NSView

    /// Never a zero size: VLCKit's OpenGL view on the Mac asserts (and the
    /// app aborts) when it draws at 0×0 — which a host mid-layout, before
    /// SwiftUI has sized it, briefly is.
    final class HostView: NSView {
        override func layout() {
            super.layout()
            if !bounds.isEmpty { hosted?.frame = bounds }      // VLCKit sizes its output from the drawable's frame
        }

        var hosted: NSView? {
            didSet {
                guard hosted !== oldValue else { return }
                oldValue?.removeFromSuperview()
                if let hosted {
                    if !bounds.isEmpty { hosted.frame = bounds }
                    hosted.autoresizingMask = [.width, .height]
                    addSubview(hosted)
                }
            }
        }
    }

    func makeNSView(context: Context) -> HostView {
        let host = HostView()
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        host.hosted = view
        return host
    }

    func updateNSView(_ host: HostView, context: Context) {
        host.hosted = view
    }
}
#endif

/// WebVTT text over AVPlayer, in the user's subtitle preset. (VLCKit draws
/// its own subtitles, with the preset passed to its text renderer.)
struct SubtitleOverlay: View {
    let cue: String?
    let scale: Double
    var style: SubtitleStyle = .classic
    var font: SubtitleFont = .system
    let raised: Bool
    /// Width ÷ height of the picture (nil: not known yet — the whole screen).
    var videoAspect: CGFloat? = nil
    /// Over the whole screen; false: in the split's picture, inside the safe area.
    var fullBleed = true

    var body: some View {
        GeometryReader { geo in
            if let cue {
                if Platform.isTV {
                    SubtitleText(cue, style: style, scale: scale, font: font)
                        .frame(maxWidth: geo.size.width * 0.8)
                        .position(x: geo.size.width / 2, y: geo.size.height - (raised ? 300 : 110))
                        .accessibilityIdentifier("subtitle.text")
                } else {
                    // On the picture, not the screen: in portrait the picture is
                    // a band across the middle, and the words sat far below it.
                    // Sized from the picture too (the TV's 46 pt was enormous on
                    // a phone), and clear of the controls when they're up.
                    let rect = Self.picture(in: geo.size, aspect: videoAspect)
                    let base = max(15, min(40, rect.height * 0.05))
                    let bottom = min(rect.maxY - rect.height * 0.06, geo.size.height - (raised ? Self.controlsHeight : 20))
                    SubtitleText(cue, style: style, scale: scale, font: font, baseSize: base)
                        .frame(maxWidth: rect.width * 0.88)
                        .frame(width: geo.size.width, height: max(0, bottom), alignment: .bottom)
                        .position(x: rect.midX, y: max(0, bottom) / 2)
                        .accessibilityIdentifier("subtitle.text")
                }
            }
        }
        .ignoresSafeArea(edges: fullBleed ? .all : [])
        .allowsHitTesting(false)
        .animation(nil, value: cue)
    }
}

extension SubtitleOverlay {
    /// The title and timeline at the bottom when the controls are up (off the TV).
    static var controlsHeight: CGFloat { Layout.device == .phone ? 150 : 190 }

    /// Where an aspect-fitted picture sits in a space.
    static func picture(in size: CGSize, aspect: CGFloat?) -> CGRect {
        guard let aspect, aspect > 0, size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: size) }
        let fitted = size.width / size.height > aspect
            ? CGSize(width: size.height * aspect, height: size.height)
            : CGSize(width: size.width, height: size.width / aspect)
        return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }
}

/// "Stats for nerds": which engine, which decoder, why.
struct EngineStatsView: View {
    let stats: EngineStats
    let format: VideoFormatInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(stats.engineName) · \(stats.method)").font(.caption.bold())
            Text("Video: \(stats.video)").font(.caption2)
            Text("Audio: \(stats.audio)").font(.caption2)
            HStack(spacing: 20) {
                if let mbps = stats.bitrateMbps { Text("\(mbps.formatted(.number.precision(.fractionLength(1)))) Mb/s") }
                Text("buffer \(Int(stats.bufferedSeconds))s")
                Text("dropped \(stats.droppedFrames)")
                Text("stalls \(stats.stalls)")
            }
            .font(.caption2.monospacedDigit())
            if !stats.notes.isEmpty {
                Text("Why: " + stats.notes.joined(separator: "; ")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .overVideoPanel(cornerRadius: 16)
        .frame(maxWidth: 900, alignment: .leading)
    }
}
