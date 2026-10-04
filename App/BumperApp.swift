import AppFeatures
import SwiftUI

@main
struct Bumper: App {
    init() {
        AppRoot.markProcessStart()
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
    }
}
