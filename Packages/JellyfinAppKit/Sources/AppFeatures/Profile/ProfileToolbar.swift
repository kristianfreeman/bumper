import AppCore
import Instrumentation
import DesignSystem
import SwiftUI

/// The sleep timer's choices, for a dialog (TV, iPhone, iPad) or a menu (Mac).
struct SleepTimerOptions: View {
    let timer: SleepTimer

    var body: some View {
        ForEach(SleepTimer.presets, id: \.self) { minutes in
            Button(SleepTimer.title(minutes)) { timer.set(.minutes(minutes)) }
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
        ToolbarSpacer(.flexible)                            // to the trailing end (items follow the page's leading edge)
        if app.accounts.accounts.count > 1 {
            ToolbarItem(placement: .automatic) {
                Button("Switch User", systemImage: "person.2") { app.switchToNextAccount() }
            }
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
#elseif os(iOS)
/// The iPhone's and iPad's profile corner: the trailing end of every page's
/// navigation bar — the TV button and the avatar's menu (Profile, and
/// Downloads and Settings, which have no tab here). The sleep timer is in
/// the player.
struct ProfileToolbar: ToolbarContent {
    let app: AppModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { CastButton() }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Profile", systemImage: "person.crop.circle") { app.pendingRoute = .profile }
                    .accessibilityIdentifier("menu.profile")
                if app.downloads != nil {
                    Button("Downloads", systemImage: "arrow.down.circle") { app.pendingRoute = .downloads }
                        .accessibilityIdentifier("menu.downloads")
                }
                Button("Settings", systemImage: "gearshape") { app.pendingRoute = .settings("root") }
                    .accessibilityIdentifier("menu.settings")
                if app.accounts.accounts.count > 1 {
                    Divider()
                    Button("Switch User", systemImage: "person.2") { app.switchToNextAccount() }
                }
            } label: {
                UserAvatar(size: 32).environment(app)
                    .accessibilityLabel(app.session?.account.userName ?? "Profile")
            }
            .accessibilityIdentifier("profile.avatar")
        }
        .sharedBackgroundVisibility(.hidden)                   // the picture is the button
    }
}

extension View {
    func profileToolbar(_ app: AppModel) -> some View { toolbar { ProfileToolbar(app: app) } }
}
#else
extension View {
    func profileToolbar(_ app: AppModel) -> some View { self }   // the TV pins it on each tab's page
}
#endif
