#if !os(tvOS)
import AppCore
import CoreMedia
import JellyfinAPI
import PlaybackCore
import SwiftUI

// The Apple TV's own machinery, as no-ops on iPhone, iPad and Mac, so the
// shared screens need no special cases. (The real ones: RemoteGestures,
// TopBand, TopShelfWriter, DisplayModeManager, InputTrace, SeekBench.)

/// The Siri Remote's clicks and swipes: touch and the pointer handle it here.
struct RemoteGestures: View {
    let transport: TransportModel
    let active: Bool
    let onVertical: () -> Void
    var body: some View { Color.clear.allowsHitTesting(false) }
}

/// Up to the sidebar from the top row: there's no focus engine on touch.
struct TopBand<Trailing: View>: View {
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack { Spacer(); trailing() }
    }
}

struct TabBarFocusGuide: View {
    var body: some View { Color.clear.frame(height: 0) }
}

/// No Top Shelf off the TV.
@MainActor
enum TopShelfWriter {
    static func update(_ sections: [BrowseSection], client: JellyfinClient, usage: [String: Double] = [:]) {}
}

/// The TV's frame-rate and dynamic-range matching.
@MainActor
enum DisplayModeManager {
    static var simulatedSwitch: Duration?
    static var matchingEnabled: Bool { false }
    static func request(for stream: MediaStream?) {}
    static func waitForSwitch(timeout: Duration = .seconds(4)) async {}
    static func reset() {}
}

@MainActor
enum InputTrace {
    static func install() {}
}

@MainActor
enum SeekBench {
    static func run(_ controller: PlayerController) async {}
}
#endif
