#if os(tvOS)
import AppCore
import DesignSystem
import JellyfinAPI
import SwiftUI

/// Words for the plan: "Three things — done around 11:40 PM."
enum TonightWords {
    static func summary(_ store: TonightStore) -> String {
        let slots = store.timeline
        guard let end = slots.last?.end else { return "Nothing planned yet." }
        let count = slots.count == 1 ? "One thing" : "\(["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"][min(slots.count, 8)]) things"
        let endText = end.formatted(date: .omitted, time: .shortened)
        guard let doneBy = store.plan.doneBy else { return "\(count) — done around \(endText)." }
        let over = Int(end.timeIntervalSince(doneBy) / 60)
        let byText = doneBy.formatted(date: .omitted, time: .shortened)
        return over > 0 ? "\(count) — runs \(over) minutes past \(byText)." : "\(count), done by \(byText). Playback stops then."
    }

    static func time(_ slot: TonightPlan.Slot) -> String {
        slot.start.formatted(date: .omitted, time: .shortened)
    }
}

/// Home's first collection when there's a plan.
struct TonightSection: View {
    let store: TonightStore
    var available: CGFloat
    var firstCardFocus: FocusState<Bool>.Binding? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @Environment(\.theme) private var theme

    private var width: CGFloat { ((available - 3 * Layout.cardSpacing) / 4).rounded(.down) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tonight").font(.title3.weight(.bold)).foregroundStyle(theme.primaryText)
                    Text(TonightWords.summary(store)).font(.callout).foregroundStyle(theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("collection.tonight")
                Spacer()
                TonightControls(store: store)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: Layout.cardSpacing, alignment: .top), count: 4), alignment: .leading, spacing: 44) {
                ForEach(store.timeline.prefix(8), id: \.entry.id) { slot in
                    LandscapeCard(slot.entry.item, width: width) { app.play(slot.entry.item) }
                        .overlay(alignment: .topLeading) { TimeBadge(slot: slot).padding(12) }
                        .contextMenu { ItemContextMenu(item: slot.entry.item) }
                        .accessibilityIdentifier("card.tonight.\(slot.entry.id)")
                        .modifier(FirstFocus(binding: slot.entry.id == store.timeline.first?.entry.id ? firstCardFocus : nil))
                }
            }
        }
        .padding(.horizontal, Layout.horizontalMargin)
        .focusSection()
    }
}

/// Play · Done by · Edit (and Clear on the plan's own page).
struct TonightControls: View {
    let store: TonightStore
    var showsEdit = true
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate

    var body: some View {
        HStack(spacing: 16) {
            if let first = store.plan.entries.first {
                Pill("Play Tonight", systemImage: "play.fill", size: .small, prominent: true) { app.play(first.item) }
                    .accessibilityIdentifier("tonight.play")
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
            .accessibilityIdentifier("tonight.doneBy")
            if showsEdit {
                Pill("Edit Tonight", systemImage: "list.bullet", size: .small) { navigate(.tonight) }
                    .accessibilityIdentifier("tonight.edit")
            } else if !store.isEmpty {
                Pill("Clear", systemImage: "trash", size: .small) { store.replace(with: TonightPlan()) }
            }
        }
    }
}

private struct TimeBadge: View {
    let slot: TonightPlan.Slot
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            if slot.entry.ambient { Image(systemName: "sparkles") }
            Text(slot.entry.ambient ? "Suggested · \(TonightWords.time(slot))" : TonightWords.time(slot))
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(slot.overruns ? .white : .black)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(slot.overruns ? Color.red.opacity(0.8) : Color.white.opacity(0.9), in: .capsule)
    }
}

/// The plan, as a list you can reorder.
struct TonightPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        let store = app.tonight
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tonight").font(.system(size: 56, weight: .bold)).foregroundStyle(theme.primaryText)
                    Text(TonightWords.summary(store)).font(.title3).foregroundStyle(theme.secondaryText)
                    TonightControls(store: store, showsEdit: false).padding(.top, 10)
                }
                .focusSection()
                if store.isEmpty {
                    Text("Add things from any page with “Add to Tonight” — or hold Select on a card.")
                        .font(.callout).foregroundStyle(theme.secondaryText)
                }
                VStack(spacing: 14) {
                    ForEach(store.timeline, id: \.entry.id) { slot in
                        TonightRow(slot: slot, store: store)
                    }
                }
            }
            .padding(.horizontal, Layout.horizontalMargin)
            .padding(.vertical, 50)
        }
        .background(theme.backgroundGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct TonightRow: View {
    let slot: TonightPlan.Slot
    let store: TonightStore
    @Environment(\.theme) private var theme

    var body: some View {
        let item = slot.entry.item
        HStack(spacing: 28) {
            Text(TonightWords.time(slot)).font(.headline.monospacedDigit()).foregroundStyle(slot.overruns ? .red : theme.primaryText).frame(width: 150, alignment: .leading)
            Artwork(item: item, kind: .landscape, width: 220)
                .frame(width: 220, height: 124)
                .clipShape(.rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.seriesName ?? item.name ?? "").font(.headline).foregroundStyle(theme.primaryText).lineLimit(1)
                Text([item.seriesName != nil ? item.name : nil, "\(Int(TonightPlan.remaining(item) / 60)) min", slot.entry.ambient ? "suggested" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(theme.secondaryText).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 14) {
                Pill("Earlier", systemImage: "arrow.up", size: .small) { store.move(slot.entry.id, by: -1) }
                Pill("Later", systemImage: "arrow.down", size: .small) { store.move(slot.entry.id, by: 1) }
                Pill(slot.entry.ambient ? "Not Tonight" : "Remove", systemImage: "xmark", size: .small) { store.remove(slot.entry.id) }
            }
        }
        .padding(18)
        .background(theme.surface.opacity(0.6), in: .rect(cornerRadius: 22))
        .focusSection()
    }
}
#endif
