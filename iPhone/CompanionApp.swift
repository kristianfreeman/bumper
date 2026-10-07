import AppFeatures
import Companion
import SwiftUI
import UIKit

/// Bumper on iPhone and iPad: the same app as on the TV (AppFeatures), with
/// one more tab, the Apple TV remote (live view, the queue, asking).
@main
struct BumperPhoneApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var delegate
    @State private var companion = CompanionModel()
    @State private var cast = CastLink()
    @Environment(\.scenePhase) private var phase

    init() {
        AppRoot.markProcessStart()
        // UI tests: an open menu's glass never reports its animation done, and
        // XCTest waited its full minute before every tap in one.
        if ProcessInfo.processInfo.arguments.contains("-uiTestNoAnimations") { UIView.setAnimationsEnabled(false) }
    }

    var body: some Scene {
        WindowGroup {
            // The Apple TV sits behind the TV button (like a cast button), not
            // a tab of its own: connected, what you play goes to the TV.
            AppRoot(cast: cast, castPanel: AnyView(RemoteTab().environment(companion)))
                .task {
                    cast.connect = { [companion] name in companion.cast(to: name) }
                    cast.disconnect = { [companion] in companion.stopCasting() }
                    cast.play = { [companion] id, resume, background in
                        companion.send(resume && !background ? .play(itemId: id) : .playItem(itemId: id, resume: resume, background: background))
                    }
                    cast.queue = { [companion] id, add in companion.send(add ? .addToQueue(itemId: id) : .removeFromQueue(itemId: id)) }
                    cast.playPause = { [companion] in companion.send(.playPause) }
                }
                // Settings → Apple TV Remote (the app sets `enabled` from it).
                .onChange(of: cast.enabled, initial: true) { _, on in on ? companion.startBrowsing() : companion.stopBrowsing() }
                .onChange(of: phase) { _, now in if now == .active { companion.refresh() } }
                // Watching first: a link that dropped says "Lost", not "Disconnected".
                .onChange(of: "\(companion.connectedTo ?? "")|\(companion.casting)", initial: true) { _, _ in
                    cast.watching = companion.connectedTo
                    cast.connectedTo = companion.casting ? companion.connectedTo : nil
                }
                .onChange(of: companion.tvs.map(\.name), initial: true) { _, names in cast.tvs = names }
                .onChange(of: companion.state?.playing, initial: true) { _, playing in
                    cast.nowPlaying = playing.map {
                        CastLink.NowPlaying(itemId: $0.item.id, title: $0.item.title, subtitle: $0.item.subtitle, imageURL: $0.item.imageURL,
                                            position: $0.position, duration: $0.duration, paused: $0.paused)
                    }
                }
        }
    }
}

/// Downloads finished while the app wasn't running: the system relaunches
/// it to deliver them, and waits to be told it's done.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == BackgroundDownloads.identifier else { completionHandler(); return }
        BackgroundDownloads.handleEvents(completionHandler)
    }
}

/// The TV, from the phone: find it, then see and steer what's on it.
struct RemoteTab: View {
    @Environment(CompanionModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let tv = model.connectedTo, let playing = model.state?.playing {
                    NowPlayingView(playing: playing, tv: tv)
                } else if let tv = model.connectedTo {
                    IdleView(tv: tv)
                } else {
                    ConnectView()
                }
            }
            .navigationTitle(model.connectedTo == nil ? "Your Apple TV" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        // Full height only for something playing: there's little else to show.
        .presentationDetents(model.state?.playing == nil ? [.medium] : [.large])
        .presentationDragIndicator(.visible)
    }
}

/// No TV yet: the ones on this network, or how to get one to appear.
struct ConnectView: View {
    @Environment(CompanionModel.self) private var model

    var body: some View {
        List {
            if model.tvs.isEmpty {
                Section {
                    HStack(spacing: 14) {
                        ProgressView()
                        Text("Looking for your Apple TV…")
                    }
                } footer: {
                    Text("Open the app on your Apple TV, on the same network as this phone.")
                }
            } else {
                Section("On this network") {
                    ForEach(model.tvs) { tv in
                        Button { model.connect(tv) } label: { Label(tv.name, systemImage: "appletv") }
                            .accessibilityIdentifier("tv.\(tv.name)")
                    }
                }
            }
        }
    }
}

struct ItemRow: View {
    let item: CompanionItem
    let detail: String?

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.imageURL) { $0.resizable().aspectRatio(16 / 9, contentMode: .fill) } placeholder: { Color.secondary.opacity(0.2) }
                .frame(width: 96, height: 54)
                .clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(1)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }
}
