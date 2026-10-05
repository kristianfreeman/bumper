#if os(tvOS)
import AppCore
import AVKit
import DesignSystem
import Instrumentation
import JellyfinAPI
import PlaybackCore
import StoreKit
import SwiftUI

// MARK: - Shared

func engineTitle(_ e: EnginePreference) -> String {
    switch e {
    case .automatic: "Automatic"
    case .vlc: "Always VLCKit"
    }
}

let bitrateOptions: [Int?] = [nil] + [120, 80, 40, 20, 10, 4].map { $0 * 1_000_000 }

func bitrateTitle(_ bits: Int?) -> String {
    bits.map { "\($0 / 1_000_000) Mbps" } ?? "Original"
}

/// A frame of "video" with a subtitle on it, drawn by the player's own
/// renderer at TV scale.
struct SubtitlePreview: View {
    let style: SubtitleStyle
    let scale: Double
    var font: SubtitleFont = .system
    var width: CGFloat = 640

    var body: some View {
        ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(red: 0.95, green: 0.78, blue: 0.55), Color(red: 0.35, green: 0.55, blue: 0.75), Color(red: 0.1, green: 0.12, blue: 0.2)], startPoint: .topTrailing, endPoint: .bottomLeading)
                Circle().fill(.white.opacity(0.85)).frame(width: width * 0.19).offset(x: width * 0.25, y: -width * 0.31)   // a bright "sun": the hard case
                SubtitleText("I never said she stole\nmy money.", style: style, scale: scale, font: font)
                    .scaleEffect(width / 1920 * 1.86)      // TV-scale text in a frame a fraction of the TV's width
                    .padding(.bottom, width * 0.03)
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(.rect(cornerRadius: 24))
            .animation(.easeOut(duration: 0.15), value: style)
            .animation(.easeOut(duration: 0.15), value: scale)
            .animation(.easeOut(duration: 0.15), value: font)
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
