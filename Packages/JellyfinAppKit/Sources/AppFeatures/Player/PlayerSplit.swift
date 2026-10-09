import AppCore
import DesignSystem
import JellyfinAPI
import PlaybackCore
import SwiftUI

/// Where the picture goes: the whole screen, or a band across the top with
/// the controls and what's around it below — when the space is taller than
/// wide (a phone or iPad upright, a tall Mac window), or iPhone Duo is half
/// folded on its side (the fold divides it: the picture above, the panel
/// below). Split by choice in a wide space (an iPad on its side, a wide Mac
/// window): side by side, the picture on the left with what it is under
/// it, the panel down the right.
struct PlayerSplit: Equatable {
    /// The picture's height; nil: the whole screen.
    let pictureHeight: CGFloat?
    /// Where the panel starts: under the picture, past the fold.
    let panelTop: CGFloat
    /// Side by side: the picture's width (the panel is right of it).
    var pictureWidth: CGFloat? = nil

    var isSplit: Bool { pictureHeight != nil }
    var isSideBySide: Bool { pictureWidth != nil }
    static let full = PlayerSplit(pictureHeight: nil, panelTop: 0)

    init(pictureHeight: CGFloat?, panelTop: CGFloat, pictureWidth: CGFloat? = nil) {
        self.pictureHeight = pictureHeight
        self.panelTop = panelTop
        self.pictureWidth = pictureWidth
    }

    /// The panel's width beside the picture: a third of the space, 340–420 pt.
    static func railWidth(_ width: CGFloat) -> CGFloat { min(max(width * 0.32, 340), 420).rounded() }

    /// Wide enough to sit side by side (an iPad on its side, a wide Mac window).
    static func sideBySide(_ size: CGSize, fold: CGRect?) -> Bool {
        fold == nil && size.width > size.height * 1.1 && size.width >= 900
    }

    /// The picture as wide as the space (up to half its height), or the half
    /// above the fold; side by side, as wide as the space left of the panel.
    init(size: CGSize, fold: CGRect?, aspect: CGFloat?) {
        if let fold {
            pictureHeight = fold.minY
            panelTop = fold.maxY
        } else if Self.sideBySide(size, fold: fold) {
            let width = size.width - Self.railWidth(size.width)
            pictureWidth = width
            pictureHeight = min(width / max(0.5, aspect ?? 16 / 9), size.height * 0.75).rounded()
            panelTop = 0
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

    /// Whether the space can take a split at all: room for a picture and a
    /// panel under it. A phone on its side (~370 pt high) hasn't — a sliver of
    /// picture over a squashed panel — so it stays full screen and offers no
    /// split; an iPad, an open iPhone Duo or a Mac window has.
    static func canSplit(_ size: CGSize, fold: CGRect?) -> Bool {
        fold != nil || size.height >= 480
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
    var picture: PictureFrame { PictureFrame(height: pictureHeight, width: pictureWidth, bleeds: true) }
    /// What sits on the picture (skip, the ±10 s badges): always inside the safe area.
    var pictureArea: PictureFrame { PictureFrame(height: pictureHeight, width: pictureWidth, bleeds: false) }
}

struct PictureFrame: ViewModifier {
    let height: CGFloat?
    var width: CGFloat? = nil
    let bleeds: Bool

    func body(content: Content) -> some View {
        content
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: width == nil ? .top : .topLeading)
            .ignoresSafeArea(edges: bleeds && height == nil ? .all : [])
    }
}

#if !os(tvOS)
/// Under the split's picture (or beside it): subtitles, audio and playback
/// (always up; play, skip and the timeline are on the picture), then what
/// it is and Up Next / About. Find Subtitles opens here rather than in a
/// sheet over it.
struct PlayerPanel: View {
    let controller: PlayerController
    let engine: any PlayerEngine
    let close: () -> Void
    let poke: () -> Void
    let fullScreen: () -> Void
    @Binding var findingSubtitles: Bool
    /// Side by side: what it is goes under the picture instead (`WatchHeader`).
    var sideBySide = false

    var body: some View {
        VStack(spacing: 0) {
            TouchControls(controller: controller, engine: engine, close: close, poke: poke,
                          findingSubtitles: $findingSubtitles, showsInfo: .constant(false), style: .menus, split: fullScreen)
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
                WatchPanelContent(controller: controller, showsHeader: !sideBySide)
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
#endif
