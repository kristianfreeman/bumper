#if os(tvOS)
import Instrumentation
import UIKit

/// Holding Left runs focus along a row as fast as it goes; at the row's
/// start it ran on, out of the page and into the sidebar, which opened, and
/// the page lost its place. Held, a move stops at the page's edge: focus
/// that runs out of the page (into UIKit's sidebar, out of SwiftUI's own
/// items) goes straight back. A fresh press still opens the sidebar.
@MainActor
enum HeldMoveGuard {
    /// Held this long, it's a run, not a press.
    static let held: TimeInterval = 0.35
    private static var down: [UIPress.PressType: Date] = [:]

    static func pressed(_ type: UIPress.PressType) { down[type] = .now }
    static func released(_ type: UIPress.PressType) { down[type] = nil }

    static func check(_ context: UIFocusUpdateContext, system: UIFocusSystem?) {
        guard context.focusHeading.contains(.left), let since = down[.leftArrow], Date.now.timeIntervalSince(since) > held,
              let previous = context.previouslyFocusedItem, let next = context.nextFocusedItem,
              !(previous is UIView), next is UIView else { return }
        TraceFile.write("focus", "held left ran out of the page (into \(type(of: next))): back to where it was")
        system?.requestFocusUpdate(to: previous)
    }
}
#endif
