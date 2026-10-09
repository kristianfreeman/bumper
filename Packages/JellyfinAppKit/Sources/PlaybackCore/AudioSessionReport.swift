public import Foundation
import Instrumentation
#if os(tvOS) || os(iOS)
import AVFoundation
import AVKit
#endif

/// Everything the audio session says about where the sound goes, on one
/// line of the trace — to find what (if anything) tells an Apple TV
/// AirPlaying to a Sonos apart from one playing over HDMI: the route says
/// HDMI and the latency 80 ms either way.
public enum AudioSessionReport {
    #if os(tvOS) || os(iOS)
    @MainActor private static var detector: AVRouteDetector?
    @MainActor private static var observers: [NSObjectProtocol] = []
    #endif

    /// Writes the report now, and again whenever the route, the rendering
    /// mode or the media services change.
    @MainActor public static func start() {
        #if os(tvOS) || os(iOS)
        guard detector == nil else { return }
        let d = AVRouteDetector()
        d.isRouteDetectionEnabled = true
        detector = d
        write("launch")
        var names: [(Notification.Name, String)] = [
            (AVAudioSession.routeChangeNotification, "route change"),
            (AVAudioSession.mediaServicesWereResetNotification, "media services reset"),
            (.AVRouteDetectorMultipleRoutesDetectedDidChange, "route detector"),
        ]
        if #available(iOS 17.2, tvOS 17.2, *) {
            names.append((AVAudioSession.renderingModeChangeNotification, "rendering mode change"))
            names.append((AVAudioSession.renderingCapabilitiesChangeNotification, "rendering capabilities change"))
        }
        for (name, why) in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                var reason = why
                if let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt { reason += " (reason \(raw))" }
                MainActor.assumeIsolated { write(reason) }
            })
        }
        #endif
    }

    @MainActor public static func write(_ when: String) {
        TraceFile.write("audio", "\(when): \(describe())")
    }

    @MainActor public static func describe() -> String {
        #if os(tvOS) || os(iOS)
        let s = AVAudioSession.sharedInstance()
        var parts: [String] = []
        parts.append("category \(s.category.rawValue) mode \(s.mode.rawValue) policy \(s.routeSharingPolicy.rawValue)")
        parts.append(String(format: "rate %.0f (preferred %.0f) buffer %.1f ms latency out %.1f ms",
                            s.sampleRate, s.preferredSampleRate, s.ioBufferDuration * 1000, s.outputLatency * 1000))
        parts.append("channels \(s.outputNumberOfChannels)/\(s.maximumOutputNumberOfChannels)")
        parts.append("other audio \(s.isOtherAudioPlaying) silence hint \(s.secondaryAudioShouldBeSilencedHint)")
        parts.append("prompt \(s.promptStyle.rawValue)")
        if #available(iOS 17.2, tvOS 17.2, *) { parts.append("rendering \(s.renderingMode.rawValue)") }
        parts.append("detector multiple \(detector?.multipleRoutesDetected ?? false)")
        for o in s.currentRoute.outputs {
            var p = "out \(o.portType.rawValue) '\(o.portName)' uid \(o.uid)"
            p += " ch[\((o.channels ?? []).map { "\($0.channelName)#\($0.channelNumber)/\($0.channelLabel)" }.joined(separator: ","))]"
            p += " sources[\((o.dataSources ?? []).map(\.dataSourceName).joined(separator: ","))] selected \(o.selectedDataSource?.dataSourceName ?? "-")"
            p += " spatial \(o.isSpatialAudioEnabled) voice \(o.hasHardwareVoiceCallProcessing)"
            parts.append(p)
        }
        return parts.joined(separator: " | ")
        #else
        return "no audio session"
        #endif
    }
}
