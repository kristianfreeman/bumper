#if !os(tvOS)
import DesignSystem
import PlaybackCore
import SwiftUI

/// The player off the TV: a close button, and back / play-pause / forward in
/// the middle, over the TV's own transport bar (whose timeline drags here).
/// The remote's gestures stand in for all of this on the TV.
struct TouchControls: View {
    let controller: PlayerController
    let engine: any PlayerEngine
    let close: () -> Void
    let poke: () -> Void
    /// A phone's menus (subtitles, audio, info) sit up here, by Close.
    var open: ((PlayerMenu) -> Void)? = nil
    @Environment(\.verticalSizeClass) private var vertical

    private var playing: Bool { engine.status != .paused }
    /// A phone on its side: less height, so smaller buttons.
    private var short: Bool { vertical == .compact }

    var body: some View {
        ZStack {
            VStack {
                HStack(spacing: 14) {
                    Pill("Close", systemImage: "xmark", size: Layout.device == .phone ? .small : .regular) { close() }
                        .accessibilityIdentifier("player.close")
                    Spacer()
                    if let open, Layout.device == .phone {
                        ForEach(PlayerMenu.allCases, id: \.self) { menu in
                            Pill(menu.title, systemImage: menu.symbol, size: .small) { open(menu) }
                                .accessibilityIdentifier("control.\(menu.rawValue)")
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, Layout.horizontalMargin)
            .padding(.top, 8)
            HStack(spacing: Layout.device == .phone ? (short ? 64 : 44) : 72) {
                button("gobackward.10", "Back 10 seconds", size: short ? 24 : 30) { Task { await controller.skip(by: .seconds(-10)) } }
                button(playing ? "pause.fill" : "play.fill", playing ? "Pause" : "Play", size: short ? 34 : 44) { controller.togglePlayPause() }
                    .accessibilityIdentifier("player.playPause")
                button("goforward.30", "Forward 30 seconds", size: short ? 24 : 30) { Task { await controller.skip(by: .seconds(30)) } }
            }
        }
    }

    private func button(_ symbol: String, _ label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            action()
            poke()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size * 2, height: size * 2)
                .background(.black.opacity(0.25), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
#endif
