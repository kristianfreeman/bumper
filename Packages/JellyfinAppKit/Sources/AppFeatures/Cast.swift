import AppCore
import DesignSystem
public import Foundation
public import Observation
public import SwiftUI

/// The iPhone/iPad's link to an Apple TV running the app (the companion),
/// like a cast button: one tap on the TV button connects, and from then on
/// Play, Background and Queue anywhere in the app go to the TV, while the
/// phone carries on browsing. Connected or not, whatever the TV is playing
/// shows above the tabs (the phone keeps a quiet link to it to know).
/// The app sets it from its companion model; nil where there's none (the
/// TV itself, the Mac).
@MainActor
@Observable
public final class CastLink {
    /// What the TV is playing, for the bar above the tabs.
    public struct NowPlaying: Equatable, Sendable {
        public var itemId: String
        public var title: String
        public var subtitle: String?
        public var imageURL: URL?
        public var position: Double
        public var duration: Double
        public var paused: Bool

        public init(itemId: String, title: String, subtitle: String?, imageURL: URL?, position: Double, duration: Double, paused: Bool) {
            self.itemId = itemId
            self.title = title
            self.subtitle = subtitle
            self.imageURL = imageURL
            self.position = position
            self.duration = duration
            self.paused = paused
        }
    }

    /// A short message at the top of the app: connected, disconnected,
    /// started on the TV.
    public struct Notice: Equatable, Identifiable, Sendable {
        public let id = UUID()
        public var title: String
        public var detail: String?
        public var symbol: String
    }

    /// The TV it's casting to, by name: what's played goes there.
    public var connectedTo: String? {
        didSet {
            guard connectedTo != oldValue else { return }
            // Connecting needs no notice: the bar above the tabs says so.
            if connectedTo == nil, let tv = oldValue {
                notice = Notice(title: watching == nil ? "Lost \(tv)" : "Disconnected from \(tv)",
                                detail: "What you play now plays on this \(Self.deviceWord).", symbol: "tv.slash")
            }
        }
    }
    /// The TV the phone watches (even when not casting): its name.
    public var watching: String?
    /// The TVs on this network running the app, by name.
    public var tvs: [String] = []
    public var nowPlaying: NowPlaying?
    /// Whether any TV has been seen on the network.
    public var available: Bool { !tvs.isEmpty }
    public var isConnected: Bool { connectedTo != nil }
    public var notice: Notice?
    /// Settings → Remote: off, the phone doesn't look for TVs, and the TV
    /// button and bar go.
    public var enabled = true

    /// "12:04", "1:02:10".
    static func clock(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    static var deviceWord: String {
        switch Layout.device { case .pad: "iPad"; case .mac: "Mac"; default: "iPhone" }
    }

    @ObservationIgnored public var connect: (String) -> Void = { _ in }
    @ObservationIgnored public var disconnect: () -> Void = {}
    /// Plays an item on the TV: (id, resume, background).
    @ObservationIgnored public var play: (String, Bool, Bool) -> Void = { _, _, _ in }
    /// Adds to (true) or takes out of (false) the TV's Queue.
    @ObservationIgnored public var queue: (String, Bool) -> Void = { _, _ in }
    @ObservationIgnored public var playPause: () -> Void = {}

    public init() {}
}

extension EnvironmentValues {
    @Entry var castLink: CastLink? = nil
    /// The TV's remote (what's on it, its Queue, search), from the
    /// connection menu and the bar above the tabs.
    @Entry var castPanel: AnyView? = nil
}

#if os(iOS)
/// The TV button: one tap connects (to the only TV there is; with several,
/// pick one). Connected, it's lit, and opens a menu: the remote, or
/// disconnect.
struct CastButton: View {
    @Environment(\.castLink) private var cast
    @Environment(\.castPanel) private var panel
    @State private var showsRemote = false

    var body: some View {
        if let cast, cast.enabled {
            Group {
                if !cast.isConnected, cast.tvs.count == 1, let tv = cast.tvs.first {
                    Button { cast.connect(tv) } label: { label(cast) }
                } else {
                    Menu {
                        if let tv = cast.connectedTo {
                            Section("Playing to \(tv)") {
                                if panel != nil {
                                    Button("Remote and Queue", systemImage: "appletv") { showsRemote = true }
                                }
                                Button("Disconnect", systemImage: "xmark", role: .destructive) { cast.disconnect() }
                            }
                        } else if cast.tvs.isEmpty {
                            Section("Looking for your Apple TV…") {
                                Text("Open \(Brand.displayName) on your Apple TV, on the same network.")
                            }
                        } else {
                            Section("Play to") {
                                ForEach(cast.tvs, id: \.self) { tv in
                                    Button(tv, systemImage: "appletv") { cast.connect(tv) }
                                }
                            }
                        }
                    } label: { label(cast) }
                }
            }
            .accessibilityIdentifier("cast.button")
            .sensoryFeedback(.success, trigger: cast.connectedTo) { old, new in old == nil && new != nil }
            .sheet(isPresented: $showsRemote) { RemoteSheet() }
        }
    }

    private func label(_ cast: CastLink) -> some View {
        Label(cast.connectedTo.map { "Connected to \($0)" } ?? "Play on Apple TV",
              systemImage: cast.isConnected ? "tv.fill" : "tv")
            .foregroundStyle(cast.isConnected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
    }
}

/// The TV's remote (what's on it, and what's next), as a sheet.
private struct RemoteSheet: View {
    @Environment(\.castPanel) private var panel

    var body: some View {
        panel                                       // sizes itself (presentationDetents)
    }
}

/// Above the tabs whenever the TV is playing something (connected or not),
/// or while connected: what's on, how far in, and play/pause. A tap opens
/// the remote.
struct CastBar: View {
    let cast: CastLink
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var showsRemote = false

    var body: some View {
        HStack(spacing: 12) {
            Button { showsRemote = true } label: {
                HStack(spacing: 12) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cast.nowPlaying?.title ?? "Connected to \(cast.connectedTo ?? "Apple TV")")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cast.bar")
            if let playing = cast.nowPlaying {
                Button { cast.playPause() } label: {
                    Image(systemName: playing.paused ? "play.fill" : "pause.fill").font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 36, height: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playing.paused ? "Play on the TV" : "Pause the TV")
                .accessibilityIdentifier("cast.playPause")
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)                        // the text sits clear of the progress line
        .frame(maxHeight: .infinity)                // the bar's full height: the line runs along its foot
        .overlay(alignment: .bottom) { progress }
        .animation(.default, value: cast.nowPlaying?.paused)
        .sheet(isPresented: $showsRemote) { RemoteSheet() }
    }

    /// "Living Room · 12:04 of 42:10 · Paused"
    private var detail: String {
        guard let playing = cast.nowPlaying else { return "Play anything and it starts on the TV" }
        let tv = cast.connectedTo ?? cast.watching.map { "On \($0)" }
        var parts = [tv, playing.subtitle].compactMap { $0 }
        if placement != .inline, playing.duration > 0 { parts.append("\(Self.clock(playing.position)) of \(Self.clock(playing.duration))") }
        if playing.paused { parts.append("Paused") }
        return parts.joined(separator: " · ")
    }

    /// How far in, as a hairline along the bar's bottom edge.
    @ViewBuilder private var progress: some View {
        if let playing = cast.nowPlaying, playing.duration > 0 {
            GeometryReader { geo in
                Capsule().fill(.tint)
                    .frame(width: geo.size.width * min(1, max(0, playing.position / playing.duration)), height: 2)
                    .animation(.linear(duration: 0.5), value: playing.position)
            }
            .frame(height: 2)
            .padding(.horizontal, 24)
            .padding(.bottom, 3)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if let url = cast.nowPlaying?.imageURL {
            AsyncImage(url: url) { $0.resizable().aspectRatio(16 / 9, contentMode: .fill) } placeholder: { Color.secondary.opacity(0.2) }
                .frame(width: 48, height: 27)
                .clipShape(.rect(cornerRadius: 5))
        } else {
            Image(systemName: "tv.fill").font(.body).foregroundStyle(.tint).frame(width: 48)
        }
    }

    static func clock(_ seconds: Double) -> String { CastLink.clock(seconds) }
}

/// The notice at the top of the app ("Connected to Living Room"): drops in,
/// stays a few seconds, and goes (a swipe up sends it sooner).
struct CastNoticeBanner: View {
    let cast: CastLink

    var body: some View {
        VStack {
            if let notice = cast.notice {
                HStack(spacing: 12) {
                    Image(systemName: notice.symbol).font(.title3).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(notice.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if let detail = notice.detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 440)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(notice.id)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("cast.notice")
                .gesture(DragGesture().onEnded { if $0.translation.height < -10 { cast.notice = nil } })
                .task(id: notice.id) {
                    try? await Task.sleep(for: .seconds(3.5))
                    if cast.notice?.id == notice.id { cast.notice = nil }
                }
            }
            Spacer()
        }
        .animation(.spring(duration: 0.4, bounce: 0.25), value: cast.notice)
    }
}

extension View {
    /// The TV bar above the tabs (while something plays on the TV, or while
    /// connected), and the notices at the top.
    @ViewBuilder func castBar(_ cast: CastLink?) -> some View {
        if let cast {
            let shown = cast.enabled && (cast.isConnected || cast.nowPlaying != nil)
            Group {
                if #available(iOS 26.1, *) {
                    tabViewBottomAccessory(isEnabled: shown) { CastBar(cast: cast) }
                } else if shown {
                    // iOS 26.0: an accessory always shows, so only while there's one.
                    tabViewBottomAccessory { CastBar(cast: cast) }
                } else {
                    self
                }
            }
            .overlay { CastNoticeBanner(cast: cast) }
        } else {
            self
        }
    }
}
#endif
