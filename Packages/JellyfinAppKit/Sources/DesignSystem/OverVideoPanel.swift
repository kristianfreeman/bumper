public import AppCore
public import SwiftUI

/// Which visual effects this Apple TV can afford over live video.
nonisolated public enum EffectsTier {
    /// A10X (2017) and A12 (2021): Liquid Glass re-blurs the playing video
    /// every frame, which costs the picture its frame rate. `-simulateModel`
    /// (launch argument → NSArgumentDomain) overrides for testing.
    public static let lightweight: Bool = {
        let model = UserDefaults.standard.string(forKey: "simulateModel") ?? PerfRecorder.hardwareModel
        return ["AppleTV5,3", "AppleTV6,2", "AppleTV11,1"].contains(model)
    }()
}

extension View {
    /// Background for panels drawn on top of playing video: Liquid Glass
    /// where it's cheap, a solid translucent fill (no blur) where it isn't.
    @ViewBuilder
    public func overVideoPanel(cornerRadius: CGFloat) -> some View {
        if EffectsTier.lightweight {
            background(Color.black.opacity(0.78), in: .rect(cornerRadius: cornerRadius))
        } else {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
