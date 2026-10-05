import AppFeatures
import SwiftUI

/// Bumper on the Mac: the TV's app (AppFeatures), in a window.
@main
struct BumperMacApp: App {
    init() { AppRoot.markProcessStart() }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
