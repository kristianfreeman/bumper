import Companion
import SwiftUI

@main
struct CompanionApp: App {
    @State private var model = CompanionModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Group {
                    if model.connectedTo == nil { ConnectView() } else { TVView() }
                }
                .navigationTitle(model.connectedTo ?? "Your Apple TV")
            }
            .environment(model)
            .task { model.startBrowsing() }
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

/// Connected: the TV, live — and Tonight, search and asking.
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
                        Button { model.send(.addToTonight(itemId: focused.id)) } label: {
                            Label(state?.tonight.contains { $0.id == focused.id } == true ? "In Tonight" : "Add to Tonight", systemImage: "moon.stars")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("phone.addFocused")
                    }
                }
                .accessibilityIdentifier("phone.focused")
            }
            Section {
                ForEach(state?.tonight ?? []) { entry in
                    ItemRow(item: entry.item, detail: (entry.suggested ? "Suggested · " : "") + entry.start.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(entry.overruns ? .red : .primary)
                }
                .onDelete { offsets in
                    for i in offsets { if let id = state?.tonight[i].id { model.send(.removeFromTonight(itemId: id)) } }
                }
                .onMove { from, to in
                    guard let i = from.first, let id = state?.tonight[i].id else { return }
                    model.send(.moveInTonight(itemId: id, by: (to > i ? to - 1 : to) - i))
                }
                DoneByRow(doneBy: state?.doneBy) { model.send(.setDoneBy($0)) }
            } header: {
                Text("Tonight")
            } footer: {
                Text(state?.tonightSummary ?? "")
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
                                Button { model.send(.addToTonight(itemId: item.id)) } label: { Label("Tonight", systemImage: "moon.stars") }.tint(.indigo)
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
