#if os(tvOS)
import AVFoundation
import AVKit
import CoreMedia
import Instrumentation
import JellyfinAPI
import PlaybackCore
import UIKit

/// Switches the TV's refresh rate and dynamic range to match the content
/// (24p film at 24 Hz, HDR10/Dolby Vision in the matching mode).
///
/// The switch is requested *before* the engine loads, from server metadata,
/// so the TV's 1–2 s HDMI resync overlaps with PlaybackInfo + demux open
/// instead of adding to time-to-first-frame.
@MainActor
enum DisplayModeManager {
    private static var displayManager: AVDisplayManager? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        // The simulator's UIWindow doesn't implement AVKit's display-manager
        // category; only real Apple TV hardware does.
        guard let window = scene?.windows.first, window.responds(to: NSSelectorFromString("avDisplayManager")) else { return nil }
        return window.avDisplayManager
    }

    /// Test hook (`-simulateModeSwitch <ms>`): the simulator has no HDMI mode
    /// switch, so this stands in for one to measure the overlap.
    static var simulatedSwitch: Duration?
    private static var simulatedSwitchEnds: ContinuousClock.Instant?

    /// Whether the user enabled Match Frame Rate / Dynamic Range in tvOS Settings.
    static var matchingEnabled: Bool { displayManager?.isDisplayCriteriaMatchingEnabled ?? false }

    static func request(for stream: MediaStream?) {
        if let simulatedSwitch, stream != nil {
            simulatedSwitchEnds = .now + simulatedSwitch
            return
        }
        guard let manager = displayManager else { return }
        guard manager.isDisplayCriteriaMatchingEnabled else {
            TraceFile.write("display", "Match Frame Rate is off in the TV's Settings: no switch (\(stream.map { "\($0.realFrameRate ?? $0.averageFrameRate ?? 0) fps" } ?? "no stream"))")
            return
        }
        guard let stream else { return }
        let fps = Float(stream.realFrameRate ?? stream.averageFrameRate ?? 0)
        guard fps > 0, let format = synthesizeFormat(stream) else {
            TraceFile.write("display", "no frame rate in the stream's details: no switch")
            return
        }
        let key = "\(fps) \(stream.videoRangeType ?? "SDR")"
        guard key != requested else { return }                     // asked already (the item's, then the plan's)
        requested = key
        requestedAt = .now
        manager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate: fps, formatDescription: format)
        Perf.event("display.criteria", "\(fps) fps \(stream.videoRangeType ?? "SDR")")
        TraceFile.write("display", "asked for \(fps) fps \(stream.videoRangeType ?? "SDR")")
    }

    private static var requested: String?
    private static var requestedAt: ContinuousClock.Instant?

    /// Waits (bounded) for an in-flight HDMI mode switch to finish so the
    /// first frames aren't lost to a blanked screen.
    static func waitForSwitch(timeout: Duration = .seconds(4)) async {
        if let ends = simulatedSwitchEnds {
            try? await Task.sleep(until: ends)
            simulatedSwitchEnds = nil
            return
        }
        guard let manager = displayManager, let asked = requestedAt else { return }
        // The switch doesn't show as in progress the moment it's asked for:
        // give it until ~400 ms after the request to start (none starts when
        // the TV is already in that mode), then wait for it to finish.
        let start = ContinuousClock.now
        while !manager.isDisplayModeSwitchInProgress, asked.duration(to: .now) < .milliseconds(400) {
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard manager.isDisplayModeSwitchInProgress else { return }
        let deadline = ContinuousClock.now + timeout
        while manager.isDisplayModeSwitchInProgress && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        TraceFile.write("display", "switched in \(Int(start.duration(to: .now).milliseconds)) ms (waited for it)")
    }

    static func reset() {
        displayManager?.preferredDisplayCriteria = nil
        requested = nil
        requestedAt = nil
    }

    /// AVDisplayCriteria decides the mode from codec type + colour
    /// extensions, so a synthetic description built from Jellyfin's stream
    /// metadata is enough — no need to wait for the first decoded frame.
    static func synthesizeFormat(_ stream: MediaStream) -> CMFormatDescription? {
        var ext: [String: Any] = [:]
        switch (stream.colorPrimaries ?? "").lowercased() {
        case "bt2020": ext[kCMFormatDescriptionExtension_ColorPrimaries as String] = kCMFormatDescriptionColorPrimaries_ITU_R_2020
        default: ext[kCMFormatDescriptionExtension_ColorPrimaries as String] = kCMFormatDescriptionColorPrimaries_ITU_R_709_2
        }
        switch (stream.colorTransfer ?? "").lowercased() {
        case "smpte2084": ext[kCMFormatDescriptionExtension_TransferFunction as String] = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
        case "arib-std-b67": ext[kCMFormatDescriptionExtension_TransferFunction as String] = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG
        default: ext[kCMFormatDescriptionExtension_TransferFunction as String] = kCMFormatDescriptionTransferFunction_ITU_R_709_2
        }
        let codec: CMVideoCodecType = stream.isDolbyVision && stream.dvProfile != 7 ? kCMVideoCodecType_DolbyVisionHEVC
            : (stream.codec == "hevc" ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264)
        var fd: CMFormatDescription?
        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: codec, width: Int32(stream.width ?? 1920), height: Int32(stream.height ?? 1080), extensions: ext as CFDictionary, formatDescriptionOut: &fd)
        return fd
    }
}
#endif
