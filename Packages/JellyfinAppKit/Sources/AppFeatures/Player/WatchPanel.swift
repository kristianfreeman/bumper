import AppCore
import DesignSystem
import JellyfinAPI
import PlaybackCore
import SwiftUI

#if !os(tvOS)
/// The watch page under (or beside) the picture: what it is, then Up Next —
/// what plays after this, and adding to it — or About.
struct WatchPanelContent: View {
    let controller: PlayerController
    /// What it is (facts and badges) at the top; side by side it's under the picture.
    var showsHeader = true
    @State private var tab: Tab = .upNext
    @State private var adding = false

    enum Tab: String, CaseIterable, Identifiable {
        case upNext = "Up Next", about = "About"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showsHeader { WatchHeader(controller: controller) }
                Picker("Show", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("watch.tabs")
                switch tab {
                case .upNext:
                    UpNextList(controller: controller) { adding = true }
                case .about:
                    WatchAbout(controller: controller)
                }
            }
            .padding(.horizontal, Layout.device == .phone ? 16 : 28)     // in line with the controls
            .padding(.top, 14)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $adding) { AddToUpNextSheet(controller: controller) }
    }
}

/// What's playing: its name, "Harbor Lights · S1 · E4 · 41m · TV-14", and
/// what the file is (4K, HDR10, 5.1, CC). When it ends is by the controls.
struct WatchHeader: View {
    let controller: PlayerController

    var body: some View {
        let item = controller.item
        VStack(alignment: .leading, spacing: 8) {
            Text(item.name ?? "").font(.title3.bold()).lineLimit(2)
            Text(ItemAbout.facts(item)).font(.footnote).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
            let badges = MediaSource.badges(controller.plan?.mediaSource ?? item.mediaSources?.first)
            if !badges.isEmpty {
                HStack(spacing: 6) { ForEach(badges, id: \.self) { Badge($0) } }
                    .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What plays after this one, in order, each with when it ends; tap one to
/// play it now. Then Add to Up Next.
struct UpNextList: View {
    let controller: PlayerController
    let add: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let list = controller.upNextList
        let ends = controller.upNextEnds(now: app.queue.now)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, next in
                let words = ItemAbout.nextLines(next, after: controller.item)
                Button { app.play(next) } label: {
                    HStack(spacing: 12) {
                        Artwork(item: next, kind: .landscape, width: 112)
                            .frame(width: 112, height: 63)
                            .clipShape(.rect(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(words.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(detail(next, first: i == 0, ends: i < ends.count ? ends[i] : nil, words: words.detail))
                                .font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if app.queue.contains(next.id) {
                        Button("Remove from Up Next", systemImage: "minus.circle", role: .destructive) { controller.removeFromUpNext(next.id) }
                    }
                }
                .accessibilityIdentifier("upnext.\(next.id)")
            }
            if list.isEmpty {
                Text("Nothing's next. The player closes when this ends.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                    .padding(.vertical, 8)
            }
            if controller.canAddToUpNext {
                Button(action: add) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .frame(width: 112, height: 63)
                            .overlay { Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.8)) }
                        Text("Add to Up Next").font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("upnext.add")
            }
        }
    }

    private func detail(_ next: BaseItem, first: Bool, ends: Date?, words: String?) -> String {
        var parts: [String] = []
        if first { parts.append("Next") } else if controller.isSuggested(next.id) { parts.append("Suggested") }
        if let words { parts.append(words) } else if let runtime = next.runtime { parts.append(MetadataLine.runtimeString(runtime)) }
        if let ends { parts.append("ends \(ends.formatted(date: .omitted, time: .shortened))") }
        return parts.joined(separator: " · ")
    }
}

/// About: what happens (spoiler-safe), and who's in it.
private struct WatchAbout: View {
    let controller: PlayerController

    var body: some View {
        let item = controller.item
        VStack(alignment: .leading, spacing: 14) {
            ItemAbout(controller: controller, showsName: false, showsSide: false)
            if let starring = ItemAbout.starring(item) {
                credit("Starring", starring)
            }
            if let director = ItemAbout.director(item) {
                credit("Directed by", director)
            }
        }
    }

    private func credit(_ label: String, _ names: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.6))
            Text(names).font(.footnote.weight(.semibold))
        }
    }
}

/// Add to Up Next: the rest of the show, things like it, and what's next
/// in your other shows; + adds to the end, ✓ takes it out again.
struct AddToUpNextSheet: View {
    let controller: PlayerController
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let sections = controller.addSections
                if sections.isEmpty {
                    Text("Nothing to suggest yet.").foregroundStyle(.secondary)
                }
                ForEach(sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.items, id: \.id) { other in row(other) }
                    }
                }
            }
            .navigationTitle("Add to Up Next")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .frame(minWidth: Platform.isMac ? 460 : nil, minHeight: Platform.isMac ? 520 : nil)
        .accessibilityIdentifier("upnext.sheet")
    }

    private func row(_ other: BaseItem) -> some View {
        let queued = app.queue.contains(other.id)
        let automatic = controller.isAutomatic(other.id)
        return HStack(spacing: 12) {
            Artwork(item: other, kind: .landscape, width: 96)
                .frame(width: 96, height: 54)
                .clipShape(.rect(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                let words = ItemAbout.nextLines(other, after: controller.item)
                Text(words.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let detail = words.detail ?? other.runtime.map(MetadataLine.runtimeString) {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if automatic {
                Text("Plays next").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            } else {
                Button { controller.toggleUpNext(other) } label: {
                    Image(systemName: queued ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(queued ? "Take \(other.name ?? "it") out of Up Next" : "Add \(other.name ?? "it") to Up Next")
                .accessibilityIdentifier("upnext.toggle.\(other.id)")
            }
        }
    }
}
#endif
