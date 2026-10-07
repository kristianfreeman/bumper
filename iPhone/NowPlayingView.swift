import Companion
import SwiftUI

/// What the TV is playing, steered from the phone, like Music's player: the
/// art, where it is, the transport, the TV's tracks and timers, then what
/// comes next.
struct NowPlayingView: View {
    @Environment(CompanionModel.self) private var model
    let playing: CompanionNowPlaying
    let tv: String
    /// The scrubber while it's dragged, and after, until the TV catches up.
    @State private var scrub: Double?
    @State private var findingSubtitles = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                art
                VStack(alignment: .leading, spacing: 3) {
                    Text("On \(tv)").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    Text(playing.item.title).font(.title2.bold()).lineLimit(2)
                        .accessibilityIdentifier("phone.playingTitle")
                    if let subtitle = playing.item.subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                }
                scrubber
                transport
                if playing.subtitles != nil {
                    // Its own view, equal unless a setting changed: the position
                    // ticking every half second rebuilt an open menu under the finger.
                    TrackControls(playing: playing, findingSubtitles: $findingSubtitles).equatable()
                }
                upNext
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .animation(.default, value: playing.paused)
        .sheet(isPresented: $findingSubtitles, onDismiss: { model.send(.cancelSubtitleSearch) }) {
            FindSubtitlesSheet(search: model.state?.playing?.subtitleSearch) { id in
                model.send(.useFoundSubtitle(id: id))
            }
        }
    }

    // MARK: Pieces

    private var art: some View {
        AsyncImage(url: playing.backdropURL ?? playing.item.imageURL) { $0.resizable().aspectRatio(16 / 9, contentMode: .fill) } placeholder: {
            Rectangle().fill(.quaternary)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: .black.opacity(playing.paused ? 0.1 : 0.3), radius: playing.paused ? 6 : 18, y: 8)
        .scaleEffect(playing.paused ? 0.92 : 1)                       // as Music does: smaller while paused
        .animation(.spring(duration: 0.4, bounce: 0.2), value: playing.paused)
    }

    private var scrubber: some View {
        let length = max(1, playing.duration)
        let at = min(length, scrub ?? playing.position)
        return VStack(spacing: 4) {
            Slider(value: Binding(get: { at }, set: { scrub = $0 }), in: 0...length) { editing in
                guard !editing, let to = scrub else { return }
                model.send(.seek(to: to))
                Task { try? await Task.sleep(for: .seconds(1.5)); if scrub == to { scrub = nil } }
            }
            .accessibilityIdentifier("phone.scrubber")
            HStack {
                Text(clock(at))
                Spacer()
                Text("−" + clock(length - at))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transport: some View {
        HStack(spacing: 48) {
            Button { model.send(.skip(by: -10)) } label: { Image(systemName: "gobackward.10").font(.title) }
                .accessibilityLabel("Back 10 seconds")
            Button { model.send(.playPause) } label: {
                Image(systemName: playing.paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 44))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel(playing.paused ? "Play" : "Pause")
            .accessibilityIdentifier("phone.playPause")
            Button { model.send(.skip(by: 30)) } label: { Image(systemName: "goforward.30").font(.title) }
                .accessibilityLabel("Ahead 30 seconds")
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var upNext: some View {
        if let next = playing.upNext, !next.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Up Next").font(.headline)
                ForEach(next) { item in
                    Button { model.send(.play(itemId: item.id)) } label: {
                        ItemRow(item: item, detail: item.subtitle).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Plays it on the TV now")
                }
            }
        }
    }
}

/// Subtitles, audio, Untracked, sleep: each says what it's set to.
struct TrackControls: View, Equatable {
    @Environment(CompanionModel.self) private var model
    let playing: CompanionNowPlaying
    @Binding var findingSubtitles: Bool

    nonisolated static func == (a: TrackControls, b: TrackControls) -> Bool {
        a.playing.subtitles == b.playing.subtitles && a.playing.subtitle == b.playing.subtitle
            && a.playing.audio == b.playing.audio && a.playing.audioTrack == b.playing.audioTrack
            && a.playing.untracked == b.playing.untracked && a.playing.sleep == b.playing.sleep
            && a.playing.sleepLabel == b.playing.sleepLabel && a.playing.kind == b.playing.kind
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Menu {
                Picker("Subtitles", selection: Binding(get: { playing.subtitle }, set: { model.send(.selectSubtitle($0)) })) {
                    Text("Off").tag(Int?.none)
                    ForEach(playing.subtitles ?? []) { track in
                        Text([track.title, track.detail].compactMap { $0 }.joined(separator: " · ")).tag(Int?.some(track.id))
                    }
                }
                Divider()
                Button("Find Subtitles…", systemImage: "magnifyingglass") {
                    model.send(.findSubtitles)
                    findingSubtitles = true
                }
            } label: {
                control(playing.subtitle == nil ? "captions.bubble" : "captions.bubble.fill",
                        playing.subtitles?.first { $0.id == playing.subtitle }?.title ?? "Subtitles Off")
            }
            .accessibilityLabel("Subtitles")
            .accessibilityValue(playing.subtitles?.first { $0.id == playing.subtitle }?.title ?? "Off")
            .accessibilityIdentifier("phone.subtitles")
            Menu {
                Picker("Audio", selection: Binding(get: { playing.audioTrack }, set: { if let id = $0 { model.send(.selectAudio(id)) } })) {
                    ForEach(playing.audio ?? []) { track in
                        Text([track.title, track.detail].compactMap { $0 }.joined(separator: " · ")).tag(Int?.some(track.id))
                    }
                }
            } label: {
                control("speaker.wave.2", playing.audio?.first { $0.id == playing.audioTrack }?.title ?? "Audio")
            }
            .disabled((playing.audio?.count ?? 0) < 2)
            Button { model.send(.setUntracked(!(playing.untracked ?? false))) } label: {
                control("infinity", "Untracked", on: playing.untracked == true)
            }
            .accessibilityValue(playing.untracked == true ? "On" : "Off")
            Menu {
                Picker("Stop Playing", selection: Binding(get: { playing.sleep ?? .off }, set: { model.send(.setSleep($0)) })) {
                    Text("Never").tag(CompanionSleep.off)
                    ForEach([15, 30, 60], id: \.self) { m in
                        Text(m < 60 ? "In \(m) Minutes" : "In 1 Hour").tag(CompanionSleep.minutes(m))
                    }
                    Text(playing.kind == "episode" ? "After This Episode" : playing.kind == "film" ? "After This Film" : "After This One")
                        .tag(CompanionSleep.endOfItem)
                }
            } label: {
                control(playing.sleep == nil || playing.sleep == .off ? "moon" : "moon.fill", sleepCaption)
            }
        }
        .buttonStyle(.plain)
    }

    private var sleepCaption: String {
        guard let label = playing.sleepLabel else { return "Stop Playing" }
        return playing.sleep == .endOfItem ? "Stops after this" : "Stops in \(label)"
    }

    /// An icon over what it's set to; on, in the tint.
    private func control(_ symbol: String, _ caption: String, on: Bool = false) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3).frame(height: 26)
            Text(caption).font(.caption).lineLimit(1).foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
    }

}

/// Find Subtitles on the TV, from the phone: the TV's server searches, the
/// results come back best first, and one tap puts it on.
struct FindSubtitlesSheet: View {
    let search: CompanionSubtitleSearch?
    let use: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: String?

    var body: some View {
        NavigationStack {
            Group {
                switch search {
                case .results(let found) where !found.isEmpty:
                    List(found) { sub in
                        Button {
                            chosen = sub.id
                            use(sub.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sub.name).lineLimit(2)
                                    Text(sub.detail).font(.caption).foregroundStyle(sub.id == found.first?.id ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                }
                                Spacer(minLength: 8)
                                if chosen == sub.id { ProgressView() }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(chosen != nil)
                    }
                case .results:
                    ContentUnavailableView("Nothing Found", systemImage: "captions.bubble", description: Text("Your server found no subtitles for this."))
                case .failed(let message):
                    ContentUnavailableView("Couldn't Find Subtitles", systemImage: "exclamationmark.bubble", description: Text(message))
                case .searching, nil:
                    if chosen == nil {
                        ProgressView("Searching…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Picked, and the TV is done with the search: it's on.
                        Color.clear.task { dismiss() }
                    }
                }
            }
            .navigationTitle("Find Subtitles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Connected, with nothing on: a half sheet — the TV, and its Queue as
/// what's up next.
struct IdleView: View {
    @Environment(CompanionModel.self) private var model
    let tv: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(systemName: "appletv").font(.title).foregroundStyle(.secondary)
                        .frame(width: 64, height: 64)
                        .background(.quaternary, in: .rect(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("On \(tv)").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Nothing Playing").font(.title3.bold()).accessibilityIdentifier("phone.idleTitle")
                        Text("Play something here and it starts on the TV.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
                if let queue = model.state?.queue, !queue.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Up Next").font(.headline)
                        ForEach(queue.prefix(6)) { entry in
                            Button { model.send(.play(itemId: entry.id)) } label: {
                                ItemRow(item: entry.item, detail: entry.item.subtitle).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

/// "12:04", "1:02:10".
func clock(_ seconds: Double) -> String {
    let s = Int(max(0, seconds))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}
