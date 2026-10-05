import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import PlaybackCore
import SwiftUI

/// Settings on one page: who's signed in, then a few short sections of
/// tiles. A switch flips where it is; a choice opens a row of options under
/// its section (no pages to dig through). Only the full theme gallery and
/// the device report are pages of their own.
struct SettingsView: View {
    /// A section to start at (deep links: `-route settings:subtitles`).
    var start: String? = nil
    @Environment(AppModel.self) private var app
    @Environment(ThemeStore.self) private var themes
    @Environment(\.theme) private var theme
    @Environment(\.navigate) private var navigate
    @State private var editing: String?
    @State private var preview: (setting: String, option: String)?
    @State private var width: CGFloat = 1600
    @State private var cleared = false
    @State private var confirmSignOut = false
    @FocusState private var focus: SettingsFocus?

    var body: some View {
        @Bindable var settings = app.settings
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 64) {
                    header
                    AccountCard(confirmSignOut: $confirmSignOut)
                        .id("account")
                    section("watching", "Watching", "Around what you watch.", [
                        .toggle("autoplay", "Play Next Episode", "forward.end", "Starts the next episode when the credits begin.", $settings.autoplayNextEpisode),
                        .toggle("intros", "Skip Intros", "forward", "Skips intros and recaps without asking.", $settings.skipIntrosAutomatically),
                        .toggle("spoilers", "Hide Spoilers", "eye.slash", "Unwatched episodes show the show's art, not a still, and no description.", $settings.hideSpoilers),
                        .choice("music", "Theme Music", "music.note", "Plays a show's theme song on its page.",
                                options: [("off", "Off"), ("shows", "Shows"), ("all", "Shows and Movies")],
                                current: !settings.playThemeMusic ? "off" : settings.themeMusicForMovies ? "all" : "shows") { v in
                                    settings.playThemeMusic = v != "off"
                                    settings.themeMusicForMovies = v == "all"
                                },
                        .toggle("themesOnline", "Find Missing Theme Songs", "globe", "For shows your server has no theme song for.", $settings.onlineThemeFallback),
                    ])
                    subtitles(settings)
                    section("picture", "Picture and Sound", "How things play.", [
                        .choice("engine", "Player", "play.rectangle", engineHelp(settings.enginePreference),
                                options: [(EnginePreference.automatic.rawValue, "Automatic"), (EnginePreference.vlc.rawValue, "Always VLCKit")],
                                current: settings.enginePreference.rawValue) { settings.enginePreference = EnginePreference(rawValue: $0) ?? .automatic },
                        .choice("bitrate", "Maximum Bitrate", "speedometer", "Above this, the server lowers the quality to fit.",
                                options: bitrateOptions.map { (bitrateKey($0), bitrateTitle($0)) },
                                current: bitrateKey(settings.maxBitrate)) { settings.maxBitrate = Int($0) },
                        .toggle("match", "Match Frame Rate and Range", "tv", "Switches the TV to each video's frame rate and HDR format.", $settings.matchContent),
                        .toggle("atmos", "Dolby Atmos Passthrough", "hifispeaker", "Sends Dolby audio to your receiver as is.", $settings.preferPassthrough),
                    ])
                    look
                    section("audiobooks", "Audiobooks", "Listening.", [
                        .choice("rate", "Speed", "gauge.with.dots.needle.50percent", "Voices keep their pitch at any speed.",
                                options: audiobookRates.map { (String($0), rateTitle($0)) },
                                current: String(settings.audiobookRate)) { settings.audiobookRate = Double($0) ?? 1 },
                        .toggle("smart", "Smart Speed", "waveform", "Shortens silences, so books finish sooner without sounding faster.", $settings.smartSpeed),
                    ])
                    section("about", "About", "\(Brand.displayName) \(Brand.version) (\(Brand.build)). Open source; themes are the only purchase.", aboutTiles(settings))
                }
                .padding(.horizontal, Layout.horizontalMargin)
                .padding(.vertical, 60)
            }
            .scrollClipDisabled()
            // The scroll view's width (the screen's), not the content's: measuring the content
            // sized it from its own first guess, and stayed TV-wide on an iPhone.
            .onGeometryChange(for: CGFloat.self) { $0.size.width - 2 * Layout.horizontalMargin } action: { width = $0 }
            .onAppear {
                guard let start else { return }
                // Focus decides where a tvOS page sits: put it in the section
                // (scrolling alone is undone by focus landing on Sign Out).
                let first = ["watching": "autoplay", "subtitles": "subMode", "picture": "engine", "audiobooks": "rate", "about": "capabilities"][start]
                Task {
                    for _ in 0..<6 {
                        try? await Task.sleep(for: .milliseconds(80))
                        if let first { focus = .tile(first) }
                        proxy.scrollTo(start, anchor: .top)
                    }
                }
            }
        }
        .background(theme.backgroundGradient.ignoresSafeArea())
        .hidesNavigationBar()
        .tvExitCommand(perform: editing == nil ? nil : { close() })
        .confirmationDialog("Sign out of \(app.session?.server.name ?? "this server")?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { app.signOut() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.system(size: Layout.pageTitle, weight: .bold)).foregroundStyle(theme.primaryText)
            Text("Everything in one place. Switches flip where they are; choices open right here.")
                .font(.title3).foregroundStyle(theme.secondaryText)
        }
    }

    // MARK: Sections

    private var columns: Int { Layout.device == .phone ? 1 : Layout.device == .pad && width < 900 ? 2 : 3 }
    private var tileWidth: CGFloat { ((width - CGFloat(columns - 1) * 30) / CGFloat(columns)).rounded(.down) }

    private func section(_ id: String, _ title: String, _ lede: String, _ tiles: [SettingTile]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionTitle(title: title, lede: lede)
            TileGrid(tiles: tiles, columns: columns) { tileView($0) }
            choices(for: tiles)
        }
        .tvFocusSection()                 // Down from any column lands in the next section
        .id(id)
    }

    @ViewBuilder
    private func tileView(_ tile: SettingTile, width: CGFloat? = nil) -> some View {
        Button { activate(tile) } label: {
            SettingTileFace(tile: tile, open: editing == tile.id)
                .frame(width: width ?? tileWidth)
        }
        .buttonStyle(PillButtonStyle())
        .focused($focus, equals: .tile(tile.id))
        .accessibilityIdentifier("setting.\(tile.id)")
        .accessibilityValue(tile.valueText)
    }

    /// The open choice's options, under its section.
    @ViewBuilder
    private func choices(for tiles: [SettingTile]) -> some View {
        if let editing, let tile = tiles.first(where: { $0.id == editing }), case .choice(let options, let current, _) = tile.kind {
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(options, id: \.key) { option in
                        Pill(option.title, systemImage: option.key == current ? "checkmark" : "circle", size: .small,
                             active: option.key == current, alwaysShowsTitle: true) { pick(tile, option.key) }
                            .focused($focus, equals: .option(tile.id, option.key))
                            .onFocused { preview = (tile.id, option.key) }
                            .accessibilityIdentifier("setting.\(tile.id).\(option.key)")
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 6)
            }
            .scrollClipDisabled()
            .tvFocusSection()
            .id(editing)
            .onAppear { focusCurrent(of: tile) }
        }
    }

    // MARK: Subtitles: a live preview beside the tiles

    private func subtitles(_ settings: AppSettings) -> some View {
        let tiles: [SettingTile] = [
            .choice("subMode", "Show Subtitles", "captions.bubble", "In your preferred language, when there are some.",
                    options: [SubtitleMode.always, .serverDefault, .forcedOnly, .off].map { ($0.rawValue, $0.title) },
                    current: settings.subtitleMode.rawValue) { settings.subtitleMode = SubtitleMode(rawValue: $0) ?? .always },
            .choice("subStyle", "Style", "textformat", "How the words sit on the picture.",
                    options: SubtitleStyle.allCases.map { ($0.rawValue, $0.title) },
                    current: settings.subtitleStyle.rawValue) { settings.subtitleStyle = SubtitleStyle(rawValue: $0) ?? .classic },
            .choice("subFont", "Font", "character", "Styled subtitles (ASS/SSA) keep their own.",
                    options: SubtitleFont.allCases.map { ($0.rawValue, $0.title) },
                    current: settings.subtitleFont.rawValue) { settings.subtitleFont = SubtitleFont(rawValue: $0) ?? .system },
            .choice("subSize", "Size", "textformat.size", "Relative to the screen.",
                    options: SubtitleSize.options.map { (String($0.scale), $0.title) },
                    current: String(SubtitleSize.options.min { abs($0.scale - settings.subtitleScale) < abs($1.scale - settings.subtitleScale) }?.scale ?? 1)) {
                        settings.subtitleScale = Double($0) ?? 1
                    },
        ]
        // While choosing, the focused option shows in the preview.
        let previewing = editing != nil ? preview : nil
        let style = previewing?.setting == "subStyle" ? SubtitleStyle(rawValue: previewing!.option) ?? settings.subtitleStyle : settings.subtitleStyle
        let font = previewing?.setting == "subFont" ? SubtitleFont(rawValue: previewing!.option) ?? settings.subtitleFont : settings.subtitleFont
        let scale = previewing?.setting == "subSize" ? Double(previewing!.option) ?? settings.subtitleScale : settings.subtitleScale
        let half = ((width - 30) / 2).rounded(.down)
        return VStack(alignment: .leading, spacing: 24) {
            SectionTitle(title: "Subtitles", lede: "\(style.title) · \(font.title) · \(SubtitleSize.title(for: scale)).")
            HStack(alignment: .top, spacing: 30) {
                SubtitlePreview(style: style, scale: scale, font: font, width: half)
                TileGrid(tiles: tiles, columns: 2) { tileView($0, width: ((half - 30) / 2).rounded(.down)) }
            }
            choices(for: tiles)
        }
        .tvFocusSection()                 // the preview isn't focusable: the whole width leads to the tiles
        .id("subtitles")
    }

    // MARK: Look: themes right here

    private var look: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionTitle(title: "Look", lede: "\(themes.theme.name) — \(themes.theme.tagline)")
            ScrollView(.horizontal) {
                HStack(spacing: 30) {
                    ForEach(Theme.signature) { t in
                        Button { themes.select(t) } label: {
                            ThemePreview(theme: t, selected: t.id == theme.id, locked: t.isPremium && !themes.isUnlocked)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("setting.theme.\(t.id)")
                    }
                    Button { navigate(.settings("themes")) } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: "square.grid.3x3.fill").font(.system(size: 44))
                                .frame(width: 240, height: 135)
                                .background(theme.surface, in: .rect(cornerRadius: 18))
                            Text("All Themes").font(.callout.weight(.semibold))
                            Text("\(Theme.all.count) themes and accents").font(.caption2).foregroundStyle(theme.secondaryText)
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("settings.themes")
                }
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
        .tvFocusSection()
        .id("look")
    }

    private func aboutTiles(_ settings: AppSettings) -> [SettingTile] {
        @Bindable var settings = settings
        var tiles: [SettingTile] = [
            .link("capabilities", "This Apple TV", "cpu", "What it can decode and send to your TV.", value: app.capabilities.hdrEligible ? "HDR" : "SDR") { navigate(.settings("capabilities")) },
            .toggle("hud", "Performance Overlay", "gauge.with.dots.needle.67percent", "Frame timing, memory and playback stats on screen.", $settings.showPerformanceHUD),
            .action("caches", "Clear Caches", "trash", "Removes saved artwork and pages. They load again from the server.", value: cleared ? "Cleared" : nil) {
                Task { await ImagePipeline.shared.removeAll(); await ContentCache.shared.removeAll(); cleared = true }
            },
            .link("source", "Source Code", "chevron.left.forwardslash.chevron.right", "Bumper is open source.", value: Brand.sourceCodeURL.host() ?? "") {},
        ]
        #if DEBUG
        tiles.append(.link("budgets", "Performance Budgets", "stopwatch", "Debug builds only.", value: nil) { navigate(.settings("budgets")) })
        #endif
        return tiles
    }

    // MARK: Behaviour

    private func activate(_ tile: SettingTile) {
        switch tile.kind {
        case .toggle(let binding): binding.wrappedValue.toggle()
        case .choice: editing = editing == tile.id ? nil : tile.id
        case .action(_, let run), .link(_, let run): run()
        }
    }

    private func pick(_ tile: SettingTile, _ key: String) {
        if case .choice(_, _, let set) = tile.kind { set(key) }
        close(focusing: tile.id)
    }

    private func close(focusing id: String? = nil) {
        let target = id ?? editing
        editing = nil
        preview = nil
        Task {
            // The closing row takes focus with it: put it back on the tile.
            for _ in 0..<6 {
                try? await Task.sleep(for: .milliseconds(40))
                if let target { focus = .tile(target) }
            }
        }
    }

    private func focusCurrent(of tile: SettingTile) {
        guard case .choice(_, let current, _) = tile.kind else { return }
        Task {
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(50))
                guard editing == tile.id else { return }
                if case .option(tile.id, _) = focus { return }
                focus = .option(tile.id, current)
            }
        }
    }

    private func engineHelp(_ e: EnginePreference) -> String {
        e == .automatic ? "MP4 plays in AVPlayer (Picture in Picture, AirPlay, Dolby Vision); everything else in VLCKit."
                        : "Everything plays in VLCKit. No Picture in Picture or AirPlay."
    }
}

enum SettingsFocus: Hashable { case tile(String), option(String, String) }

private let audiobookRates: [Double] = [0.8, 1.0, 1.1, 1.2, 1.3, 1.5, 1.75, 2.0, 2.5]
private func rateTitle(_ r: Double) -> String { r == 1 ? "Normal" : "\(r.formatted(.number.precision(.fractionLength(0...2))))×" }
private func bitrateKey(_ bits: Int?) -> String { bits.map(String.init) ?? "original" }

/// One setting on the page.
struct SettingTile: Identifiable {
    enum Kind {
        case toggle(Binding<Bool>)
        case choice(options: [(key: String, title: String)], current: String, set: (String) -> Void)
        case action(value: String?, run: () -> Void)
        case link(value: String?, run: () -> Void)
    }
    let id: String
    let title: String
    let symbol: String
    let detail: String
    let kind: Kind

    var valueText: String {
        switch kind {
        case .toggle(let b): b.wrappedValue ? "On" : "Off"
        case .choice(let options, let current, _): options.first { $0.key == current }?.title ?? ""
        case .action(let value, _), .link(let value, _): value ?? ""
        }
    }

    static func toggle(_ id: String, _ title: String, _ symbol: String, _ detail: String, _ binding: Binding<Bool>) -> SettingTile {
        SettingTile(id: id, title: title, symbol: symbol, detail: detail, kind: .toggle(binding))
    }
    static func choice(_ id: String, _ title: String, _ symbol: String, _ detail: String, options: [(String, String)], current: String,
                       set: @escaping (String) -> Void) -> SettingTile {
        SettingTile(id: id, title: title, symbol: symbol, detail: detail, kind: .choice(options: options.map { (key: $0.0, title: $0.1) }, current: current, set: set))
    }
    static func action(_ id: String, _ title: String, _ symbol: String, _ detail: String, value: String?, run: @escaping () -> Void) -> SettingTile {
        SettingTile(id: id, title: title, symbol: symbol, detail: detail, kind: .action(value: value, run: run))
    }
    static func link(_ id: String, _ title: String, _ symbol: String, _ detail: String, value: String?, run: @escaping () -> Void) -> SettingTile {
        SettingTile(id: id, title: title, symbol: symbol, detail: detail, kind: .link(value: value, run: run))
    }
}

/// A tile: icon, title, what it does, and its value — lifting white when focused.
private struct SettingTileFace: View {
    let tile: SettingTile
    let open: Bool
    @Environment(\.isFocused) private var focused
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Image(systemName: tile.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .frame(width: 60, height: 60)
                    .background(focused ? Color.black.opacity(0.07) : theme.primaryText.opacity(0.08), in: .circle)
                Spacer(minLength: 12)
                value
            }
            Text(tile.title).font(.headline).lineLimit(1)
            Text(tile.detail).font(.caption).opacity(0.7).lineLimit(2, reservesSpace: true)
        }
        .foregroundStyle(focused ? .black : theme.primaryText)
        .padding(24)
        .background(focused ? Color.white : theme.surface.opacity(0.75), in: .rect(cornerRadius: 26))
        .scaleEffect(focused ? 1.04 : 1)
        .shadowWhen(focused, color: .black.opacity(0.3), radius: 18, y: 10)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: focused)
    }

    @ViewBuilder
    private var value: some View {
        switch tile.kind {
        case .toggle(let b):
            // A small switch: a filled knob on the right when on.
            Capsule()
                .fill(b.wrappedValue ? (focused ? Color.black : theme.primaryText) : (focused ? Color.black.opacity(0.12) : theme.primaryText.opacity(0.15)))
                .frame(width: 64, height: 36)
                .overlay(alignment: b.wrappedValue ? .trailing : .leading) {
                    Circle().fill(b.wrappedValue ? (focused ? Color.white : theme.backgroundBottom) : (focused ? Color.black.opacity(0.45) : theme.primaryText.opacity(0.6)))
                        .frame(width: 28, height: 28).padding(4)
                }
                .animation(.spring(duration: 0.25), value: b.wrappedValue)
        case .choice:
            HStack(spacing: 8) {
                Text(tile.valueText).font(.callout.weight(.semibold)).lineLimit(1)
                Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption.weight(.bold)).opacity(0.6)
            }
        case .action(let value, _):
            if let value { Text(value).font(.callout.weight(.semibold)) }
        case .link(let value, _):
            HStack(spacing: 8) {
                if let value { Text(value).font(.callout.weight(.semibold)).lineLimit(1) }
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).opacity(0.6)
            }
        }
    }
}

/// Tiles in rows (not lazy: a lazy grid builds tiles only once they're on
/// screen, and Down from the section above found nothing to land on).
private struct TileGrid<Tile: View>: View {
    let tiles: [SettingTile]
    let columns: Int
    @ViewBuilder let tile: (SettingTile) -> Tile

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 30, verticalSpacing: 30) {
            ForEach(Array(stride(from: 0, to: tiles.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(tiles[start..<min(start + columns, tiles.count)]) { tile($0) }
                }
            }
        }
        .tvFocusSection()
    }
}

private struct SectionTitle: View {
    let title: String
    let lede: String
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(theme.primaryText)
            Text(lede).font(.callout).foregroundStyle(theme.secondaryText).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Who's signed in: switch, approve another device, sign out.
private struct AccountCard: View {
    @Binding var confirmSignOut: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var approving = false
    @State private var code = ""
    @State private var result: String?

    var body: some View {
        if let session = app.session {
            HStack(spacing: 40) {
                UserAvatar(size: 150)
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.account.userName).font(.system(size: Layout.sectionTitle, weight: .bold)).foregroundStyle(theme.primaryText)
                    Text("\(session.server.name) · \(session.server.url.host() ?? session.server.url.absoluteString)\(session.server.version.map { " · Jellyfin \($0)" } ?? "")")
                        .font(.callout).foregroundStyle(theme.secondaryText)
                    HStack(spacing: 16) {
                        ForEach(app.accounts.accounts.filter { $0.id != session.id }) { other in
                            Pill("Switch to \(other.userName)", systemImage: "person.2", size: .small, alwaysShowsTitle: true) { app.switchAccount(other.id) }
                        }
                        Pill("Approve a Device", systemImage: "iphone.and.arrow.forward", size: .small, alwaysShowsTitle: true) {
                            code = ""
                            approving = true
                        }
                        .accessibilityIdentifier("settings.approve")
                        Pill("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", size: .small, alwaysShowsTitle: true) { confirmSignOut = true }
                            .accessibilityIdentifier("settings.signOut")
                    }
                    .padding(.top, 14)
                }
                Spacer()
            }
            .padding(Platform.isTV ? 36 : 20)
            .background(theme.surface.opacity(0.55), in: .rect(cornerRadius: Platform.isTV ? 36 : 22))
            .tvFocusSection()
            // Quick Connect, the other way round: another device (a new TV,
            // phone, Mac) shows a code; entering it here signs that one in as you.
            .alert("Approve a device", isPresented: $approving) {
                TextField("Code", text: $code)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Button("Approve") { approve() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the code the other device shows to sign it in as \(session.account.userName).")
            }
            .alert(result ?? "", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
                Button("OK") { result = nil }
            }
        }
    }

    private func approve() {
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty, let client = app.session?.client else { return }
        Task {
            do {
                try await client.quickConnectAuthorize(code: digits)
                result = "Approved. The other device is signing in."
            } catch {
                result = "That code didn't work. Check it, or start again on the other device."
            }
        }
    }
}
