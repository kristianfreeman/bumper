import AppCore
import DesignSystem
import JellyfinAPI
import PlaybackCore
import SwiftUI

/// Where the picture goes: the whole screen, or a band across the top with
/// the controls and what's around it below — when the space is taller than
/// wide (a phone or iPad upright, a tall Mac window), or iPhone Duo is half
/// folded on its side (the fold divides it: the picture above, the panel below).
struct PlayerSplit: Equatable {
    /// The picture's height; nil: the whole screen.
    let pictureHeight: CGFloat?
    /// Where the panel starts: under the picture, past the fold.
    let panelTop: CGFloat

    var isSplit: Bool { pictureHeight != nil }
    static let full = PlayerSplit(pictureHeight: nil, panelTop: 0)

    init(pictureHeight: CGFloat?, panelTop: CGFloat) {
        self.pictureHeight = pictureHeight
        self.panelTop = panelTop
    }

    /// The picture as wide as the space (up to half its height), or the half above the fold.
    init(size: CGSize, fold: CGRect?, aspect: CGFloat?) {
        if let fold {
            pictureHeight = fold.minY
            panelTop = fold.maxY
        } else {
            let height = min(size.width / max(0.5, aspect ?? 16 / 9), size.height * 0.5).rounded()
            pictureHeight = height
            panelTop = height
        }
    }

    /// By the space's shape (the choice can override it either way).
    static func splits(_ size: CGSize, fold: CGRect?) -> Bool {
        fold != nil || size.height > size.width * 1.1
    }

    /// The fold across the space (iPhone Duo on its side, half open), when
    /// there's one: the top half for watching, the bottom one to touch.
    /// iOS 27.1's reserved regions; nothing elsewhere, or built with an
    /// older SDK.
    static func fold(in proxy: GeometryProxy) -> CGRect? {
        #if os(iOS) && canImport(SwiftUICore, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            let across = proxy.reservedRegions(kind: .division)
                .first { $0.isActive && $0.frame.width > $0.frame.height }
            if let frame = across?.frame, frame.minY > 120, frame.maxY < proxy.size.height - 120 { return frame }
        }
        #endif
        return nil
    }

    /// The picture's own layers (video, subtitles, the tap target): edge to
    /// edge when full screen; in the band, inside the safe area.
    var picture: PictureFrame { PictureFrame(height: pictureHeight, bleeds: true) }
    /// What sits on the picture (skip, the ±10 s badges): always inside the safe area.
    var pictureArea: PictureFrame { PictureFrame(height: pictureHeight, bleeds: false) }
}

struct PictureFrame: ViewModifier {
    let height: CGFloat?
    let bleeds: Bool

    func body(content: Content) -> some View {
        content
            .frame(height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: bleeds && height == nil ? .all : [])
    }
}

#if !os(tvOS)
/// Under the split's picture: the controls (always up — they're not over
/// anything), then about it, what's next and the queue. Find Subtitles
/// opens here rather than in a sheet over it.
struct PlayerPanel: View {
    let controller: PlayerController
    let engine: any PlayerEngine
    let close: () -> Void
    let poke: () -> Void
    let fullScreen: () -> Void
    @Binding var findingSubtitles: Bool

    var body: some View {
        VStack(spacing: 0) {
            TouchControls(controller: controller, engine: engine, close: close, poke: poke,
                          findingSubtitles: $findingSubtitles, showsInfo: .constant(false), docked: true, split: fullScreen)
            if findingSubtitles {
                FindSubtitlesSheet(controller: controller) {
                    findingSubtitles = false
                    controller.subtitleSearch = .idle
                }
                .clipShape(.rect(cornerRadius: 20))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.opacity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        ItemAbout(controller: controller, showsName: false)
                        if controller.chapters.count > 1 { ChapterStrip(controller: controller, poke: poke) }
                        PanelQueue(current: controller.item.id)
                    }
                    .padding(.horizontal, Layout.device == .phone ? 16 : 28)     // in line with the controls
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: findingSubtitles)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        // A container of its own: on the bare stack the identifier was
        // stamped on every control in it (Close, Pause… all "player.panel").
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.panel")
    }
}

/// What the queue plays after this one.
private struct PanelQueue: View {
    let current: String
    @Environment(AppModel.self) private var app

    var body: some View {
        let later = Array(app.queue.timeline.filter { $0.entry.item.id != current }.prefix(6))
        if !later.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Queue").font(.headline)
                ForEach(later, id: \.entry.id) { slot in
                    Button { app.play(slot.entry.item) } label: {
                        HStack(spacing: 12) {
                            Artwork(item: slot.entry.item, kind: .landscape, width: 96)
                                .frame(width: 96, height: 54)
                                .clipShape(.rect(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slot.entry.item.name ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(QueueWords.time(slot)).font(.footnote).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("panel.queue.\(slot.entry.id)")
                }
            }
        }
    }
}
#endif
