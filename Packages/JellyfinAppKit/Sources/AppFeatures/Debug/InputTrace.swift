#if os(tvOS)
import Instrumentation
import UIKit

/// Every remote press and every focus change, to the trace log — so a "the
/// remote does nothing here" report can be read back from the device.
/// Cheap: a few lines per press.
@MainActor
enum InputTrace {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        NotificationCenter.default.addObserver(forName: UIFocusSystem.didUpdateNotification, object: nil, queue: .main) { note in
            let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext
            let item = context?.nextFocusedItem
            let label = (item as? NSObject)?.accessibilityLabel ?? ""
            let frame = item.map { $0.frame } ?? .zero
            TraceFile.write("focus*", "\(item.map { String(describing: type(of: $0)) } ?? "none") '\(label)' \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
        }
        Task { @MainActor in
            for _ in 0..<50 {                                     // the window arrives after launch
                if let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first {
                    let presses = PressLogger()
                    presses.cancelsTouchesInView = false
                    presses.delaysTouchesBegan = false
                    window.addGestureRecognizer(presses)
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Sees every press, claims none.
    private final class PressLogger: UIGestureRecognizer {
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
            for p in presses { TraceFile.write("press", Self.name(p.type)) }
        }
        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) { state = .failed }
        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) { state = .failed }

        static func name(_ type: UIPress.PressType) -> String {
            switch type {
            case .menu: "menu"
            case .select: "select"
            case .playPause: "play/pause"
            case .leftArrow: "left"
            case .rightArrow: "right"
            case .upArrow: "up"
            case .downArrow: "down"
            case .pageUp: "page up"
            case .pageDown: "page down"
            default: "other (\(type.rawValue))"
            }
        }
    }
}
#endif
