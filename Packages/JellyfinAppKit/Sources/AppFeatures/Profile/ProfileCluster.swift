import AppCore
import DesignSystem
import SwiftUI

/// The profile corner, pinned above every tab (not part of any page, so it
/// stays put as pages scroll): icons only, as pills — they open to show
/// their name when focused. Sleep timer (lit while one is running), switch
/// user (with more than one account), and the avatar (profile & stats).
/// The Mac puts the same controls in its window toolbar (`ProfileToolbar`).
struct ProfileCluster: View {
    @Environment(AppModel.self) private var app
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
            Pill(app.session?.account.userName ?? "Profile", detail: "Profile", size: .regular, fillsIcon: true) {
                UserAvatar(size: PillSize.regular.diameter)
            } action: {
                app.pendingRoute = .profile                       // pinned outside any page's stack
            }
            .accessibilityIdentifier("profile.avatar")
        }
        .tvFocusSection()
        // On the cluster (always present), not the button — so the sheet
        // survives the menu collapsing while it's up.
        .confirmationDialog("Sleep Timer", isPresented: $showSleepOptions, titleVisibility: .visible) {
            SleepTimerOptions(timer: timer)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(timer.isActive ? "Playback stops \(timer.mode == .endOfItem ? "when this episode ends" : "in \(timer.shortLabel ?? "")")." : "Playback fades out and stops.")
        }
    }
}

/// The sleep timer's choices, for a dialog (TV, iPhone, iPad) or a menu (Mac).
struct SleepTimerOptions: View {
    let timer: SleepTimer

    var body: some View {
        ForEach(SleepTimer.presets, id: \.self) { minutes in
            Button(minutes < 60 ? "\(minutes) Minutes" : minutes == 60 ? "1 Hour" : "\(minutes / 60) Hours \(minutes % 60) Minutes") { timer.set(.minutes(minutes)) }
        }
        Button("End of Current Episode") { timer.set(.endOfItem) }
        if timer.isActive {
            Button("Turn Off", role: .destructive) { timer.reset() }
        }
    }
}

#if os(macOS)
/// The Mac's profile corner: the window toolbar's trailing end (each page
/// brings its own toolbar, so the stack gives every page this one).
struct ProfileToolbar: ToolbarContent {
    let app: AppModel

    var body: some ToolbarContent {
        let timer = app.sleepTimer
        ToolbarSpacer(.flexible)                            // to the trailing end (items follow the page's leading edge)
        ToolbarItemGroup(placement: .automatic) {
            if app.accounts.accounts.count > 1 {
                Button("Switch User", systemImage: "person.2") { app.switchToNextAccount() }
            }
            Menu {
                SleepTimerOptions(timer: timer)
            } label: {
                Label(timer.shortLabel.map { "Sleep Timer: \($0)" } ?? "Sleep Timer", systemImage: timer.isActive ? "moon.zzz.fill" : "moon.zzz")
            }
            .help(timer.isActive ? "Sleep timer: \(timer.shortLabel ?? "on")" : "Sleep Timer")
            .accessibilityIdentifier("profile.sleep")
        }
        ToolbarItem(placement: .automatic) {
            Button { app.pendingRoute = .profile } label: {
                UserAvatar(size: 26).environment(app)
            }
            .help(app.session?.account.userName ?? "Profile")
            .accessibilityIdentifier("profile.avatar")
        }
    }
}

extension View {
    func profileToolbar(_ app: AppModel) -> some View { toolbar { ProfileToolbar(app: app) } }
}
#else
extension View {
    func profileToolbar(_ app: AppModel) -> some View { self }   // pinned over the tabs instead
}
#endif
