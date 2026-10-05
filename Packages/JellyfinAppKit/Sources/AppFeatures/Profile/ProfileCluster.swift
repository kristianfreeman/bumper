#if os(tvOS)
import AppCore
import DesignSystem
import SwiftUI

/// Top-right corner of Home: icons only, as pills — they open to show
/// their name when focused. Sleep timer (lit while one is running), switch
/// user (with more than one account), and the avatar (profile & stats).
struct ProfileCluster: View {
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @State private var showSleepOptions = false

    var body: some View {
        let timer = app.sleepTimer
        HStack(spacing: 20) {
            if app.accounts.accounts.count > 1 {
                Pill("Switch User", systemImage: "person.2", size: .small) { app.switchToNextAccount() }
            }
            Pill("Sleep Timer", systemImage: timer.isActive ? "moon.zzz.fill" : "moon.zzz", detail: timer.shortLabel, size: .small, active: timer.isActive) {
                showSleepOptions = true
            }
            .accessibilityIdentifier("profile.sleep")
            Pill(app.session?.account.userName ?? "Profile", detail: "Profile", size: .regular) {
                UserAvatar(size: 76)
            } action: {
                navigate(.profile)
            }
            .accessibilityIdentifier("profile.avatar")
        }
        .tvFocusSection()
        // On the cluster (always present), not the button — so the sheet
        // survives the menu collapsing while it's up.
        .confirmationDialog("Sleep Timer", isPresented: $showSleepOptions, titleVisibility: .visible) {
            ForEach(SleepTimer.presets, id: \.self) { minutes in
                Button(minutes < 60 ? "\(minutes) Minutes" : minutes == 60 ? "1 Hour" : "\(minutes / 60) Hours \(minutes % 60) Minutes") { timer.set(.minutes(minutes)) }
            }
            Button("End of Current Episode") { timer.set(.endOfItem) }
            if timer.isActive {
                Button("Turn Off", role: .destructive) { timer.reset() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(timer.isActive ? "Playback stops \(timer.mode == .endOfItem ? "when this episode ends" : "in \(timer.shortLabel ?? "")")." : "Playback fades out and stops.")
        }
    }
}
#endif
