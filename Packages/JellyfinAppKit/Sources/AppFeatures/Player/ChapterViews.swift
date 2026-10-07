import AppCore
import DesignSystem
import PlaybackCore
import SwiftUI

/// A chapter's picture, 16:9: its own image from the server, else the
/// trickplay frame where it starts, else a quiet placeholder.
struct ChapterThumb: View {
    let chapter: PlayerChapter
    let controller: PlayerController
    let width: CGFloat
    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "film").font(.system(size: width / 6)).foregroundStyle(.white.opacity(0.25))
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .clipShape(.rect(cornerRadius: Platform.isTV ? 10 : 6))
        .task(id: chapter) {
            let loaded = await controller.chapterImage(chapter, pixelWidth: Int(width * scale))
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

#if !os(tvOS)
/// The split's chapters, under what it's about: a row of pictures, the one
/// playing marked; tap or click one to go there.
struct ChapterStrip: View {
    let controller: PlayerController
    let poke: () -> Void
    @Environment(\.theme) private var theme
    private var width: CGFloat { Layout.device == .phone ? 150 : 180 }

    var body: some View {
        let current = controller.currentChapter
        VStack(alignment: .leading, spacing: 12) {
            Text("Chapters").font(.headline)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(controller.chapters) { chapter in
                            Button {
                                Task { await controller.seek(to: chapter.start) }
                                poke()
                            } label: {
                                cell(chapter, playing: chapter.id == current?.id)
                            }
                            .buttonStyle(.plain)
                            .id(chapter.id)
                            .accessibilityIdentifier("panel.chapter.\(chapter.index)")
                            .accessibilityValue(chapter.id == current?.id ? "playing" : "")
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                // Opened mid-film: the one playing in view, not the first.
                .onAppear { if let current { proxy.scrollTo(current.id, anchor: .leading) } }
            }
        }
    }

    private func cell(_ chapter: PlayerChapter, playing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ChapterThumb(chapter: chapter, controller: controller, width: width)
                .overlay {
                    if playing { RoundedRectangle(cornerRadius: 6).stroke(theme.accent, lineWidth: 2) }
                }
                .cardHighlight()
            Text(chapter.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(playing ? "Playing · \(chapter.start.clockString)" : chapter.start.clockString)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(playing ? theme.accent : .white.opacity(0.6))
        }
        .frame(width: width, alignment: .leading)
        .contentShape(.rect)
    }
}
#endif
