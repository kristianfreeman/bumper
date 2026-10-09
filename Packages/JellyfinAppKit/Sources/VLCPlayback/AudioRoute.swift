import Foundation
#if os(tvOS) || os(iOS)
import AVFAudio
#endif

/// Where the sound goes, as VLC's clock needs to know: AirPlay (a Sonos, a
/// HomePod) and Bluetooth hold back a second or two of audio.
///
/// An Apple TV whose sound goes to a Sonos over AirPlay says HDMI (80 ms)
/// until sound is actually playing; ~0.3 s in, the route is AirPlay with
/// 2000 ms of output latency — announced as a rendering change, not a route
/// change. So the route is read again once sound plays (`changes`), and
/// what it was then is kept for the next item (`lastPlayedDelayed`).
enum AudioRoute {
    /// Sound going somewhere that delays it.
    static var isDelayed: Bool {
        #if os(tvOS) || os(iOS)
        let delayed: Set<AVAudioSession.Port> = [.airPlay, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { delayed.contains($0.portType) }
            || outputLatency > 0.25
        #else
        return false
        #endif
    }

    /// How far behind the sound plays (seconds): 0.08 over HDMI, 2 over AirPlay.
    static var outputLatency: TimeInterval {
        #if os(tvOS) || os(iOS)
        AVAudioSession.sharedInstance().outputLatency
        #else
        0
        #endif
    }

    /// The route was delayed the last time sound played: before it plays the
    /// session says HDMI either way, so an item opens on what it was then.
    static var lastPlayedDelayed: Bool {
        get { UserDefaults.standard.bool(forKey: "audio.lastPlayedDelayed") }
        set { UserDefaults.standard.set(newValue, forKey: "audio.lastPlayedDelayed") }
    }

    /// "AirPlay: Bedroom (Sonos)", for the trace.
    static var description: String {
        #if os(tvOS) || os(iOS)
        AVAudioSession.sharedInstance().currentRoute.outputs.map { "\($0.portType.rawValue): \($0.portName)" }.joined(separator: ", ")
            + String(format: " (%.0f ms behind)", outputLatency * 1000)
        #else
        "system output"
        #endif
    }

    /// Posted when the output may have changed: a speaker chosen, a receiver
    /// turned off — and AirPlay taking over once sound plays, which comes as
    /// a rendering change.
    static var changes: [Notification.Name] {
        #if os(tvOS) || os(iOS)
        var names = [AVAudioSession.routeChangeNotification]
        if #available(iOS 17.2, tvOS 17.2, *) {
            names += [AVAudioSession.renderingCapabilitiesChangeNotification, AVAudioSession.renderingModeChangeNotification]
        }
        return names
        #else
        return []
        #endif
    }
}
