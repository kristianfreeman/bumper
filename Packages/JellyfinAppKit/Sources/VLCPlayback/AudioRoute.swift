import Foundation
#if os(tvOS) || os(iOS)
import AVFAudio
#endif

/// Where the sound goes, as VLC's clock needs to know: AirPlay (a Sonos, a
/// HomePod) and Bluetooth hold back a second or two of audio.
enum AudioRoute {
    /// Sound going somewhere that delays it.
    static var isDelayed: Bool {
        #if os(tvOS) || os(iOS)
        let delayed: Set<AVAudioSession.Port> = [.airPlay, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { delayed.contains($0.portType) }
        #else
        return false
        #endif
    }

    /// "AirPlay: Bedroom (Sonos)", for the trace.
    static var description: String {
        #if os(tvOS) || os(iOS)
        AVAudioSession.sharedInstance().currentRoute.outputs.map { "\($0.portType.rawValue): \($0.portName)" }.joined(separator: ", ")
        #else
        "system output"
        #endif
    }

    /// Posted when the output changes (a speaker chosen, a receiver turned off).
    static var changed: Notification.Name? {
        #if os(tvOS) || os(iOS)
        AVAudioSession.routeChangeNotification
        #else
        nil
        #endif
    }
}
