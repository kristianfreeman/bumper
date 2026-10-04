#if os(tvOS)
import AppCore
import AVKit
import DesignSystem
import Instrumentation
import JellyfinAPI
import PlaybackCore
import StoreKit
import SwiftUI

// MARK: - Layout

/// The tvOS Settings idiom: a visual on the left that describes whatever row
/// has focus, a short list on the right under a fixed title.
struct SettingsPage<Hero: View, Rows: View>: View {
    let title: String
    @ViewBuilder let hero: () -> Hero
    @ViewBuilder let rows: () -> Rows
    @State private var help: SettingsHelpText?

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            hero()
                .environment(\.settingsHelp, help?.text)
                .frame(width: 640)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 24) {
                Text(title)
                    .font(.title2.bold())
                    .padding(.horizontal, 20)
                List { rows() }
                    .contentMargins(.top, 28, for: .scrollContent)
                    .environment(\.setSettingsHelp, SetSettingsHelp { help = $0 ?? (help?.id == $1 ? nil : help) })
                    .mask(alignment: .top) {
                        // Rows fade out under the title instead of sliding behind it.
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 20)
                            Color.black
                        }
                    }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct SettingsHelpText: Equatable { let id: UUID; let text: String }

/// Rows report the description to show while they have focus.
struct SetSettingsHelp {
    let set: (SettingsHelpText?, UUID) -> Void
    init(_ set: @escaping (SettingsHelpText?, UUID) -> Void) { self.set = set }
}

extension EnvironmentValues {
    @Entry var settingsHelp: String? = nil
    @Entry var setSettingsHelp = SetSettingsHelp { _, _ in }
}

extension View {
    /// The description shown on the left while this row has focus.
    func settingsHelp(_ text: String?) -> some View { modifier(SettingsHelpModifier(text: text)) }
}

private struct SettingsHelpModifier: ViewModifier {
    let text: String?
    @State private var id = UUID()
    @FocusState private var focused: Bool
    @Environment(\.setSettingsHelp) private var setHelp

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: focused) { _, now in
                // Gaining focus sets this row's text; losing it clears only
                // our own (the next row may already have set its text).
                setHelp.set(now ? text.map { SettingsHelpText(id: id, text: $0) } : nil, id)
            }
    }
}

/// Big tinted symbol, with the focused row's description (or the page's
/// caption) under it.
struct SettingsGlyph: View {
    let symbol: String
    var caption: String? = nil
    @Environment(\.theme) private var theme
    @Environment(\.settingsHelp) private var help

    var body: some View {
        VStack(spacing: 36) {
            Image(systemName: symbol)
                .font(.system(size: 150, weight: .regular))
                .foregroundStyle(theme.accent)
                .frame(width: 320, height: 320)
                .background(theme.surface, in: .rect(cornerRadius: 64))
            Text(help ?? caption ?? " ")
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520, minHeight: 120, alignment: .top)
                .animation(.easeOut(duration: 0.15), value: help)
        }
        .padding(.top, 140)
    }
}

/// A row that opens a sub-page, showing its current value on the right.
/// Navigates by route through the app's one NavigationStack (view-based
/// links lose their stack inside a tab and silently do nothing).
struct SettingsLink: View {
    let title: String
    var symbol: String? = nil
    var value: String? = nil
    let page: String
    @Environment(\.navigate) private var navigate

    var body: some View {
        Button { navigate(.settings(page)) } label: {
            HStack(spacing: 22) {
                if let symbol { Image(systemName: symbol).frame(width: 44) }
                Text(title)
                Spacer()
                if let value { Text(value).foregroundStyle(.secondary) }
                Image(systemName: "chevron.right").font(.callout.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .accessibilityIdentifier("settings.\(page)")
    }
}

/// Inline single choice: one line, a checkmark on the chosen row.
struct ChoiceRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if selected { Image(systemName: "checkmark").fontWeight(.semibold) }
            }
        }
    }
}

// MARK: - Root

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(ThemeStore.self) private var themes

    var body: some View {
        let settings = app.settings
        SettingsPage(title: "Settings") {
            VStack(spacing: 28) {
                Image(systemName: "play.tv.fill")
                    .font(.system(size: 150))
                    .foregroundStyle(.tint)
                    .frame(width: 320, height: 320)
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 64))
                Text(Brand.displayName).font(.title2.bold())
                if let session = app.session {
                    Text("\(session.account.userName) · \(session.server.name)")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text("Version \(Brand.version) (\(Brand.build))").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.top, 140)
        } rows: {
            Section {
                SettingsLink(title: "Playback", symbol: "play.rectangle", value: engineTitle(settings.enginePreference), page: "playback")
                SettingsLink(title: "Subtitles", symbol: "captions.bubble", value: settings.subtitleMode.title, page: "subtitles")
                SettingsLink(title: "Appearance", symbol: "paintpalette", value: themes.theme.name, page: "appearance")
            }
            Section {
                SettingsLink(title: "Account", symbol: "person.crop.circle", value: app.session?.account.userName, page: "account")
                SettingsLink(title: "Advanced", symbol: "gauge.with.dots.needle.67percent", page: "advanced")
                SettingsLink(title: "About", symbol: "info.circle", page: "about")
            }
        }
    }
}

func engineTitle(_ e: EnginePreference) -> String {
    switch e {
    case .automatic: "Automatic"
    case .vlc: "Always VLCKit"
    }
}

private let bitrateOptions: [Int?] = [nil] + [120, 80, 40, 20, 10, 4].map { $0 * 1_000_000 }

private func bitrateTitle(_ bits: Int?) -> String {
    bits.map { "\($0 / 1_000_000) Mbps" } ?? "Original"
}

// MARK: - Pages

struct PlaybackSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        SettingsPage(title: "Playback") {
            SettingsGlyph(symbol: "play.rectangle")
        } rows: {
            Section("Player") {
                ChoiceRow(title: "Automatic", selected: settings.enginePreference == .automatic) { settings.enginePreference = .automatic }
                    .settingsHelp("MP4 files play in AVPlayer, for Picture in Picture, AirPlay and Dolby Vision. Everything else plays in VLCKit.")
                ChoiceRow(title: "Always VLCKit", selected: settings.enginePreference == .vlc) { settings.enginePreference = .vlc }
                    .settingsHelp("Everything plays in VLCKit. No Picture in Picture or AirPlay.")
            }
            Section("Quality") {
                SettingsLink(title: "Maximum Bitrate", value: bitrateTitle(settings.maxBitrate), page: "bitrate")
                    .settingsHelp("Above this, the server lowers the quality to fit.")
                Toggle("Match Frame Rate and Range", isOn: $settings.matchContent)
                    .settingsHelp("Switches the TV to each video's frame rate and HDR format.")
                Toggle("Dolby Atmos Passthrough", isOn: $settings.preferPassthrough)
                    .settingsHelp("Sends Dolby audio to your receiver as is.")
            }
            Section("Episodes") {
                Toggle("Play Next Episode", isOn: $settings.autoplayNextEpisode)
                    .settingsHelp("Starts the next episode when the credits begin.")
                Toggle("Skip Intros", isOn: $settings.skipIntrosAutomatically)
                    .settingsHelp("Skips intros and recaps without asking.")
            }
        }
    }
}

struct BitrateSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        SettingsPage(title: "Maximum Bitrate") {
            SettingsGlyph(symbol: "speedometer", caption: "Above this, the server lowers the quality to fit.")
        } rows: {
            Section {
                ForEach(bitrateOptions, id: \.self) { bits in
                    ChoiceRow(title: bitrateTitle(bits), selected: settings.maxBitrate == bits) { settings.maxBitrate = bits }
                        .settingsHelp(bits == nil ? "Never lower the quality. Best on your home network." : nil)
                }
            }
        }
    }
}

struct SubtitleSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        SettingsPage(title: "Subtitles") {
            SubtitlePreview(style: settings.subtitleStyle, scale: settings.subtitleScale, font: settings.subtitleFont)
        } rows: {
            Section("Show Subtitles") {
                ForEach([SubtitleMode.always, .serverDefault, .forcedOnly, .off]) { mode in
                    ChoiceRow(title: mode.title, selected: settings.subtitleMode == mode) { settings.subtitleMode = mode }
                        .settingsHelp(modeHelp(mode))
                }
            }
            Section("Look") {
                SettingsLink(title: "Style", value: settings.subtitleStyle.title, page: "subtitle-style")
                SettingsLink(title: "Font", value: settings.subtitleFont.title, page: "subtitle-font")
                SettingsLink(title: "Size", value: SubtitleSize.title(for: settings.subtitleScale), page: "subtitle-size")
            }
        }
    }

    private func modeHelp(_ mode: SubtitleMode) -> String? {
        switch mode {
        case .always: "In your preferred language, whenever there are subtitles."
        case .serverDefault: "Whatever each file's default is on the server."
        case .forcedOnly: "Only for dialogue in another language."
        case .off: nil
        }
    }
}

/// Choice pages for the subtitle look: focusing an option previews it.
struct SubtitleStylePage: View {
    @Environment(AppModel.self) private var app
    @State private var preview: SubtitleStyle?

    var body: some View {
        @Bindable var settings = app.settings
        SettingsPage(title: "Style") {
            SubtitlePreview(style: preview ?? settings.subtitleStyle, scale: settings.subtitleScale, font: settings.subtitleFont)
        } rows: {
            Section {
                ForEach(SubtitleStyle.allCases) { style in
                    ChoiceRow(title: style.title, selected: settings.subtitleStyle == style) { settings.subtitleStyle = style }
                        .onFocused { preview = style }
                }
            }
        }
    }
}

struct SubtitleFontPage: View {
    @Environment(AppModel.self) private var app
    @State private var preview: SubtitleFont?

    var body: some View {
        @Bindable var settings = app.settings
        SettingsPage(title: "Font") {
            SubtitlePreview(style: settings.subtitleStyle, scale: settings.subtitleScale, font: preview ?? settings.subtitleFont,
                            note: "Styled subtitles (ASS/SSA) keep their own fonts.")
        } rows: {
            Section {
                ForEach(SubtitleFont.allCases) { font in
                    ChoiceRow(title: font.title, selected: settings.subtitleFont == font) { settings.subtitleFont = font }
                        .onFocused { preview = font }
                }
            }
        }
    }
}

struct SubtitleSizePage: View {
    @Environment(AppModel.self) private var app
    @State private var preview: Double?

    var body: some View {
        @Bindable var settings = app.settings
        SettingsPage(title: "Size") {
            SubtitlePreview(style: settings.subtitleStyle, scale: preview ?? settings.subtitleScale, font: settings.subtitleFont)
        } rows: {
            Section {
                ForEach(SubtitleSize.options, id: \.scale) { option in
                    ChoiceRow(title: option.title, selected: settings.subtitleScale == option.scale) { settings.subtitleScale = option.scale }
                        .onFocused { preview = option.scale }
                }
            }
        }
    }
}

/// A frame of "video" with a subtitle on it, drawn by the player's own
/// renderer at TV scale.
struct SubtitlePreview: View {
    let style: SubtitleStyle
    let scale: Double
    var font: SubtitleFont = .system
    var note: String? = nil
    @Environment(\.settingsHelp) private var help

    var body: some View {
        VStack(spacing: 24) {
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(red: 0.95, green: 0.78, blue: 0.55), Color(red: 0.35, green: 0.55, blue: 0.75), Color(red: 0.1, green: 0.12, blue: 0.2)], startPoint: .topTrailing, endPoint: .bottomLeading)
                Circle().fill(.white.opacity(0.85)).frame(width: 120).offset(x: 160, y: -200)   // a bright "sun": the hard case
                SubtitleText("I never said she stole\nmy money.", style: style, scale: scale, font: font)
                    .scaleEffect(0.62)                     // the preview frame is ~⅓ of the TV
                    .padding(.bottom, 18)
            }
            .frame(width: 640, height: 360)
            .clipShape(.rect(cornerRadius: 24))
            .animation(.easeOut(duration: 0.15), value: style)
            .animation(.easeOut(duration: 0.15), value: scale)
            .animation(.easeOut(duration: 0.15), value: font)
            Text(help ?? note ?? "\(style.title) · \(font.title) · \(SubtitleSize.title(for: scale))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560, minHeight: 90, alignment: .top)
        }
        .padding(.top, 140)
    }
}

struct AppearanceSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(ThemeStore.self) private var themes

    var body: some View {
        @Bindable var settings = app.settings
        SettingsPage(title: "Appearance") {
            SettingsGlyph(symbol: "paintpalette")
        } rows: {
            Section {
                SettingsLink(title: "Theme", value: themes.theme.name, page: "themes")
                    .settingsHelp("Themes are the app's only purchase.")
                Toggle("Hide Spoilers", isOn: $settings.hideSpoilers)
                    .settingsHelp("Unwatched episodes show the show's artwork instead of a still, and no description.")
            }
            Section("Theme Music") {
                Toggle("Play Theme Music", isOn: $settings.playThemeMusic)
                    .settingsHelp("Plays a show's theme song on its page.")
                Toggle("Movies Too", isOn: $settings.themeMusicForMovies).disabled(!settings.playThemeMusic)
                    .settingsHelp("Plays a movie's theme song, when it has one.")
                Toggle("Find Missing Themes Online", isOn: $settings.onlineThemeFallback).disabled(!settings.playThemeMusic)
                    .settingsHelp("For shows your server has no theme song for.")
            }
        }
    }
}

struct AccountSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        SettingsPage(title: "Account") {
            SettingsGlyph(symbol: "person.crop.circle", caption: app.session.map { "Signed in to \($0.server.name)" } ?? "Not signed in")
        } rows: {
            if let session = app.session {
                Section {
                    LabeledContent("User", value: session.account.userName)
                    LabeledContent("Server", value: session.server.name)
                    LabeledContent("Server Version", value: session.server.version ?? "Unknown")
                    LabeledContent("Address", value: session.server.url.host() ?? session.server.url.absoluteString)
                }
            }
            let others = app.accounts.accounts.filter { $0.id != app.session?.id }
            if !others.isEmpty {
                Section("Switch User") {
                    ForEach(others) { account in
                        Button(account.userName) { app.switchAccount(account.id) }
                    }
                }
            }
            Section {
                Button("Sign Out", role: .destructive) { app.signOut() }
            }
        }
    }
}

struct AdvancedSettings: View {
    @Environment(AppModel.self) private var app
    @State private var cleared = false

    var body: some View {
        @Bindable var settings = app.settings
        SettingsPage(title: "Advanced") {
            SettingsGlyph(symbol: "gauge.with.dots.needle.67percent")
        } rows: {
            Section {
                Toggle("Performance Overlay", isOn: $settings.showPerformanceHUD)
                    .settingsHelp("Frame timing, memory and playback stats on screen.")
                SettingsLink(title: "Device Capabilities", page: "capabilities")
                    .settingsHelp("What this Apple TV can decode and output.")
                #if DEBUG
                SettingsLink(title: "Performance Budgets", page: "budgets")
                    .settingsHelp("Debug builds only.")
                #endif
            }
            Section {
                Button(cleared ? "Caches Cleared" : "Clear Caches") {
                    Task { await ImagePipeline.shared.removeAll(); await ContentCache.shared.removeAll(); cleared = true }
                }
                .disabled(cleared)
                .settingsHelp("Removes saved artwork and pages. They load again from the server.")
            }
        }
    }
}

struct AboutSettings: View {
    var body: some View {
        SettingsPage(title: "About") {
            SettingsGlyph(symbol: "heart.text.square", caption: "Open source. Themes are the only purchase.")
        } rows: {
            Section {
                LabeledContent("Version", value: "\(Brand.version) (\(Brand.build))")
                LabeledContent("Source Code", value: Brand.sourceCodeURL.host() ?? Brand.sourceCodeURL.absoluteString)
                LabeledContent("Playback", value: "AVPlayer and VLCKit (LGPL)")
            }
        }
    }
}

struct ThemesView: View {
    @Environment(ThemeStore.self) private var store
    @Environment(\.theme) private var current

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 50) {
                Text("Themes").font(.title2.bold())
                if !store.isUnlocked {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Unlock Every Theme").font(.title3.bold())
                        Text("Every theme and accent colour, for a one-time price.")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 30) {
                            Button {
                                Task { await store.purchase() }
                            } label: {
                                Text(store.product.map { "Unlock for \($0.displayPrice)" } ?? "Unlock")
                            }
                            .disabled(store.product == nil || store.purchaseInFlight)
                            Button("Restore Purchases") { Task { await store.restore() } }
                        }
                    }
                }
                // Grid by family: six per family, one row each (6 × 240 + 5 × 32 = 1600 pt).
                ForEach(Theme.families, id: \.name) { family in
                    VStack(alignment: .leading, spacing: 20) {
                        Text(family.name).font(.title3.bold())
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(240), spacing: 32), count: 6), alignment: .leading, spacing: 40) {
                            ForEach(family.themes) { theme in
                                Button { store.select(theme) } label: {
                                    ThemePreview(theme: theme, selected: theme.id == current.id, locked: theme.isPremium && !store.isUnlocked)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .focusSection()
                }
                if store.isUnlocked {
                    Text("Accent Colour").font(.headline)
                    HStack(spacing: 24) {
                        Button("Theme Default") { store.customAccentIndex = nil }
                        ForEach(Theme.accentPalette.indices, id: \.self) { i in
                            Button { store.customAccentIndex = i } label: {
                                Circle().fill(Theme.accentPalette[i]).frame(width: 50, height: 50)
                                    .overlay(Circle().stroke(.white, lineWidth: store.customAccentIndex == i ? 4 : 0))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .padding(80)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct ThemePreview: View {
    let theme: Theme
    let selected: Bool
    let locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                theme.backgroundGradient
                HStack(spacing: 9) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: theme.cardCornerRadius / 2)
                            .fill(i == 0 ? theme.accent : theme.surface)
                            .frame(width: 38, height: 57)
                    }
                }
                .padding(16)
            }
            .frame(width: 240, height: 135)
            .clipShape(.rect(cornerRadius: 18))
            .overlay(alignment: .topTrailing) {
                Image(systemName: locked ? "lock.fill" : selected ? "checkmark.circle.fill" : "")
                    .font(.title3).padding(16).foregroundStyle(.white)
            }
            .hoverEffect(.highlight)
            Text(theme.name).font(.callout.weight(.semibold)).lineLimit(1)
            Text(theme.tagline).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct CapabilitiesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let c = app.capabilities
        List {
            Section("Hardware Video Decode") {
                row("H.264", c.h264); row("HEVC / HEVC Main10", c.hevc); row("AV1", c.av1Hardware); row("VP9", c.vp9Hardware)
            }
            Section("VLCKit") {
                Text("MKV, AVI, TS, VC-1, MPEG-2, AV1, VP9, DTS, TrueHD, FLAC, Opus, ASS/SSA, PGS, VobSub, DVB").font(.caption)
            }
            Section("Output") {
                row("HDR Display", c.hdrEligible)
                LabeledContent("Audio Channels", value: "\(c.maxAudioChannels)")
                row("Match Content (tvOS Settings)", DisplayModeManager.matchingEnabled)
            }
        }
        .navigationTitle("Device")
    }

    private func row(_ label: String, _ on: Bool) -> some View {
        LabeledContent(label) { Image(systemName: on ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(on ? .green : .secondary) }
    }
}

#if DEBUG
struct BudgetsView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let snapshot = Metrics.shared.snapshot()
            List(PerformanceBudget.defaults, id: \.metric) { budget in
                let verdict = budget.evaluate(snapshot[budget.metric])
                LabeledContent(budget.metric.rawValue) {
                    switch verdict {
                    case .pass(let v): Text("\(Int(v)) < \(Int(budget.limit)) ms").foregroundStyle(.green)
                    case .fail(let v): Text("\(Int(v)) ≥ \(Int(budget.limit)) ms").foregroundStyle(.red)
                    case .noData: Text("no data").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Budgets (\(PerformanceBudget.Statistic.p95.rawValue))")
    }
}
#endif
#endif
