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

    init() { AppRoot.markProcessStart() }

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
                    companion.startBrowsing()
                }
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
                if model.connectedTo == nil { ConnectView() } else { TVView() }
            }
            .navigationTitle(model.connectedTo ?? "Your Apple TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
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

/// Connected: the TV, live — and Queue, search and asking.
struct TVView: View {
    @Environment(CompanionModel.self) private var model
    @State private var query = ""
    @State private var asking = ""

    var body: some View {
        let state = model.state
        List {
            if let playing = state?.playing {
                Section("Playing on the TV") {
                    ItemRow(item: playing.item, detail: "\(clock(playing.position)) of \(clock(playing.duration))")
                    Button { model.send(.playPause) } label: {
                        Label(playing.paused ? "Play" : "Pause", systemImage: playing.paused ? "play.fill" : "pause.fill")
                    }
                    .accessibilityIdentifier("phone.playPause")
                }
            }
            if let focused = state?.focused {
                Section("On your TV") {
                    FocusedCard(item: focused)
                    HStack {
                        Button { model.send(.play(itemId: focused.id)) } label: { Label("Play", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent)
                        Button { model.send(.addToQueue(itemId: focused.id)) } label: {
                            Label(state?.queue.contains { $0.id == focused.id } == true ? "In Queue" : "Add to Queue", systemImage: "text.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("phone.addFocused")
                    }
                }
            }
            Section {
                ForEach(state?.queue ?? []) { entry in
                    ItemRow(item: entry.item, detail: (entry.suggested ? "Suggested · " : "") + entry.start.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(entry.overruns ? .red : .primary)
                }
                .onDelete { offsets in
                    for i in offsets { if let id = state?.queue[i].id { model.send(.removeFromQueue(itemId: id)) } }
                }
                .onMove { from, to in
                    guard let i = from.first, let id = state?.queue[i].id else { return }
                    model.send(.moveInQueue(itemId: id, by: (to > i ? to - 1 : to) - i))
                }
                DoneByRow(doneBy: state?.doneBy) { model.send(.setDoneBy($0)) }
            } header: {
                Text("Queue")
            } footer: {
                Text(state?.queueSummary ?? "")
            }
            Section {
                TextField("Ask: something funny from the 80s…", text: $asking)
                    .onSubmit { Task { await model.ask(asking) } }
                    .submitLabel(.search)
                    .accessibilityIdentifier("phone.ask")
            } footer: {
                Text(CompanionModel.hasOnDeviceModel ? "Understood on this iPhone, then found on your TV." : "Your TV reads the request.")
            }
            if let title = model.resultsTitle {
                Section(title) {
                    ForEach(model.results) { item in
                        ItemRow(item: item, detail: item.subtitle)
                            .swipeActions {
                                Button { model.send(.addToQueue(itemId: item.id)) } label: { Label("Queue", systemImage: "text.badge.plus") }.tint(.indigo)
                                Button { model.send(.play(itemId: item.id)) } label: { Label("Play", systemImage: "play.fill") }.tint(.green)
                            }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search your library")
        .onSubmit(of: .search) { model.search(query) }
        .toolbar { EditButton() }
        .animation(.default, value: state)
    }

    private func clock(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The TV's focused title, big.
struct FocusedCard: View {
    let item: CompanionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: item.imageURL) { image in
                image.resizable().aspectRatio(16 / 9, contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary).aspectRatio(16 / 9, contentMode: .fit)
            }
            .clipShape(.rect(cornerRadius: 14))
            Text(item.title).font(.title3.bold()).accessibilityIdentifier("phone.focusedTitle")
            if let subtitle = item.subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            if let overview = item.overview { Text(overview).font(.footnote).foregroundStyle(.secondary).lineLimit(3) }
        }
        .padding(.vertical, 6)
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

struct DoneByRow: View {
    let doneBy: Date?
    let set: (Date?) -> Void
    @State private var time = Date.now.addingTimeInterval(2 * 3600)

    var body: some View {
        HStack {
            Toggle("Done by", isOn: Binding(get: { doneBy != nil }, set: { set($0 ? time : nil) }))
            if doneBy != nil {
                DatePicker("", selection: Binding(get: { doneBy ?? time }, set: { time = $0; set($0) }), displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
        }
    }
}
