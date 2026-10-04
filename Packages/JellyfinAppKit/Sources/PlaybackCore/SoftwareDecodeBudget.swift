public import Foundation
public import JellyfinAPI

/// Can this Apple TV software-decode a stream in real time?
///
/// VLCKit decodes H.264/HEVC in hardware, everything else on the CPU. 4K AV1
/// on a 2017 A10X would stutter, so the planner asks the server to
/// transcode instead. Conservative per-model priors; newer models: no limit.
public struct SoftwareDecodeBudget: Sendable {
    /// Max sustained decode rate in pixels/second, per codec (nil = no limit).
    public var limits: [String: Double]
    public var fallback: Double?

    public init(limits: [String: Double], fallback: Double?) {
        self.limits = limits
        self.fallback = fallback
    }

    static func px(_ w: Double, _ h: Double, _ fps: Double) -> Double { w * h * fps }

    /// Conservative priors by Apple TV model identifier.
    public static func forModel(_ model: String) -> SoftwareDecodeBudget {
        switch model {
        case "AppleTV6,2":                               // Apple TV 4K (2017), A10X
            return .init(limits: [
                "av1": px(1920, 1080, 30), "vp9": px(1920, 1080, 30),
                "mpeg2video": px(1920, 1080, 60), "vc1": px(1920, 1080, 30), "mpeg4": px(1920, 1080, 30),
                "h264": px(1920, 1080, 60), "hevc": px(1920, 1080, 30),
            ], fallback: px(1920, 1080, 30))
        case "AppleTV11,1":                              // Apple TV 4K (2021), A12
            return .init(limits: ["av1": px(2560, 1440, 30), "vp9": px(3840, 2160, 30)], fallback: px(3840, 2160, 30))
        default:                                         // A15 and newer, simulators
            return .init(limits: [:], fallback: nil)
        }
    }

    public func allows(codec: String, pixelRate: Double) -> Bool {
        guard let limit = limits[codec] ?? fallback else { return true }
        return pixelRate <= limit
    }
}
