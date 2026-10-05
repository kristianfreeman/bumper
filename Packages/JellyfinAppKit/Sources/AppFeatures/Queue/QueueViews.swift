import AppCore
import DesignSystem
import JellyfinAPI
import SwiftUI

/// Words for the plan: "Three things — done around 11:40 PM."
enum QueueWords {
    static func summary(_ store: QueueStore) -> String {
        let slots = store.timeline
        guard let end = slots.last?.end else { return "Nothing planned yet." }
        let count = slots.count == 1 ? "One thing" : "\(["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"][min(slots.count, 8)]) things"
        let endText = end.formatted(date: .omitted, time: .shortened)
        guard let doneBy = store.plan.doneBy else { return "\(count) — done around \(endText)." }
        let over = Int(end.timeIntervalSince(doneBy) / 60)
        let byText = doneBy.formatted(date: .omitted, time: .shortened)
        return over > 0 ? "\(count) — runs \(over) minutes past \(byText)." : "\(count), done by \(byText). Playback stops then."
    }

    static func time(_ slot: QueuePlan.Slot) -> String {
        slot.start.formatted(date: .omitted, time: .shortened)
    }
}

/// Home's first collection when there's a plan.
struct QueueSection: View {
    let store: QueueStore
    var available: CGFloat
    var firstCardFocus: FocusState<Bool>.Binding? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @Environment(\.theme) private var theme

    private var columns: Int { Layout.columns(available, minWidth: Layout.landscapeMin, max: 4) }
    private var width: CGFloat { Layout.cardWidth(available, columns: columns) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Queue").font(.title3.weight(.bold)).foregroundStyle(theme.primaryText)
                    Text(QueueWords.summary(store)).font(.callout).foregroundStyle(theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("collection.queue")
                Spacer()
                QueueControls(store: store)
            }
            // Up from the left half of the plan goes to the sidebar, not
            // across to the controls on the right (as it does on any page).
            .background(alignment: .leading) {
                TabBarFocusGuide().frame(width: available / 2)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: Layout.cardSpacing, alignment: .top), count: columns), alignment: .leading, spacing: Layout.shelfSpacing) {
                ForEach(store.timeline.prefix(8), id: \.entry.id) { slot in
                    LandscapeCard(slot.entry.item, width: width) { app.play(slot.entry.item) }
                        .overlay(alignment: .topLeading) { TimeBadge(slot: slot).padding(12) }
                        .contextMenu { ItemContextMenu(item: slot.entry.item) }
                        .accessibilityIdentifier("card.queue.\(slot.entry.id)")
                        .modifier(FirstFocus(binding: slot.entry.id == store.timeline.first?.entry.id ? firstCardFocus : nil))
                }
            }
        }
        .padding(.horizontal, Layout.horizontalMargin)
        .tvFocusSection()
    }
}

/// Play · Done by · Edit (and Clear on the plan's own page).
struct QueueControls: View {
    let store: QueueStore
    var showsEdit = true
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate

    var body: some View {
        HStack(spacing: 16) {
            if let first = store.plan.entries.first {
                Pill("Play Queue", systemImage: "play.fill", size: .small, prominent: true) { app.play(first.item) }
                    .accessibilityIdentifier("queue.play")
            }
            Menu {
                ForEach(store.doneByChoices(), id: \.self) { date in
                    Button(date.formatted(date: .omitted, time: .shortened)) { store.setDoneBy(date) }
                }
                if store.plan.doneBy != nil {
                    Button("No End Time", role: .destructive) { store.setDoneBy(nil) }
                }
            } label: {
                PillFace("Done By", detail: store.plan.doneBy?.formatted(date: .omitted, time: .shortened), size: .small, active: store.plan.doneBy != nil) {
                    PillSymbol(store.plan.doneBy == nil ? "moon.zzz" : "moon.zzz.fill", size: .small)
                }
            }
            .buttonStyle(PillButtonStyle())
            .accessibilityIdentifier("queue.doneBy")
            if showsEdit {
                Pill("Edit Queue", systemImage: "list.bullet", size: .small) { navigate(.queue) }
                    .accessibilityIdentifier("queue.edit")
            } else if !store.isEmpty {
                Pill("Clear", systemImage: "trash", size: .small) { store.replace(with: QueuePlan()) }
            }
        }
    }
}

private struct TimeBadge: View {
    let slot: QueuePlan.Slot
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            if slot.entry.ambient { Image(systemName: "sparkles") }
            Text(slot.entry.ambient ? "Suggested · \(QueueWords.time(slot))" : QueueWords.time(slot))
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(slot.overruns ? .white : .black)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(slot.overruns ? Color.red.opacity(0.8) : Color.white.opacity(0.9), in: .capsule)
    }
}

/// The plan, as a list you can reorder.
struct QueuePage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        let store = app.queue
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Queue").font(.system(size: Layout.pageTitleSmall, weight: .bold)).foregroundStyle(theme.primaryText)
                    Text(QueueWords.summary(store)).font(.title3).foregroundStyle(theme.secondaryText)
                    QueueControls(store: store, showsEdit: false).padding(.top, 10)
                }
                .tvFocusSection()
                if store.isEmpty {
                    Text("Add things from any page with “Add to Queue” — or hold Select on a card.")
                        .font(.callout).foregroundStyle(theme.secondaryText)
                }
                VStack(spacing: 14) {
                    ForEach(store.timeline, id: \.entry.id) { slot in
                        QueueRow(slot: slot, store: store)
                    }
                }
            }
            .padding(.horizontal, Layout.horizontalMargin)
            .padding(.vertical, 50)
        }
        .background(theme.backgroundGradient.ignoresSafeArea())
        .hidesNavigationBar()
    }
}

private struct QueueRow: View {
    let slot: QueuePlan.Slot
    let store: QueueStore
    @Environment(\.theme) private var theme

    var body: some View {
        let item = slot.entry.item
        HStack(spacing: 28) {
            Text(QueueWords.time(slot)).font(.headline.monospacedDigit()).foregroundStyle(slot.overruns ? .red : theme.primaryText).frame(width: 150, alignment: .leading)
            Artwork(item: item, kind: .landscape, width: 220)
                .frame(width: 220, height: 124)
                .clipShape(.rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.seriesName ?? item.name ?? "").font(.headline).foregroundStyle(theme.primaryText).lineLimit(1)
                Text([item.seriesName != nil ? item.name : nil, "\(Int(QueuePlan.remaining(item) / 60)) min", slot.entry.ambient ? "suggested" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(theme.secondaryText).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 14) {
                Pill("Earlier", systemImage: "arrow.up", size: .small) { store.move(slot.entry.id, by: -1) }
                Pill("Later", systemImage: "arrow.down", size: .small) { store.move(slot.entry.id, by: 1) }
                Pill(slot.entry.ambient ? "Not Now" : "Remove", systemImage: "xmark", size: .small) { store.remove(slot.entry.id) }
            }
        }
        .padding(18)
        .background(theme.surface.opacity(0.6), in: .rect(cornerRadius: 22))
        .tvFocusSection()
    }
}
