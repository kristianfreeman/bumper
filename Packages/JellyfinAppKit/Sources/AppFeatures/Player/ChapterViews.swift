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

