import AppFeatures
import SwiftUI

@main
struct JellyfinApp: App {
    init() {
        AppRoot.markProcessStart()
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
    }
}
