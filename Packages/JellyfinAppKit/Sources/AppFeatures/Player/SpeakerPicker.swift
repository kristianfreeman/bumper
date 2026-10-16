import AVKit
import Instrumentation
import SwiftUI

/// Settings → Speakers Button: the system's own speaker picker — AirPlay
/// speakers, a HomePod, the TV — which tvOS otherwise keeps behind Control
/// Center. The real AVRoutePickerView, in the player's controls: the system
/// draws it, focuses it and presents its picker. (Pressing a hidden one for
/// a button of ours didn't present anything on tvOS.)
#if canImport(UIKit)
struct SpeakerPickerButton: UIViewRepresentable {
    var size: CGFloat

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.prioritizesVideoDevices = false             // speakers first, not AirPlay video
        view.delegate = context.coordinator
        view.accessibilityIdentifier = "control.speakers"
        view.accessibilityLabel = "Speakers"
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AVRoutePickerView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Only writes the trace: AVKit calls these off the main thread (the
    /// picker's closing came on an XPC queue, and a main-actor method trapped).
    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        nonisolated func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            TraceFile.write("player", "speakers: the picker opened")
        }
        nonisolated func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            TraceFile.write("player", "speakers: the picker closed")
        }
    }
}
#else
struct SpeakerPickerButton: NSViewRepresentable {
    var size: CGFloat

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.setAccessibilityIdentifier("control.speakers")
        view.setAccessibilityLabel("Speakers")
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AVRoutePickerView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}
#endif
