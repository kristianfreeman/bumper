public import CoreGraphics
import Foundation
import Instrumentation

/// BlurHash decoder (https://blurha.sh). Jellyfin ships a blurhash for every
/// image, so cards show a correctly-coloured blur *instantly*, before a single
/// image byte arrives. Decoding at 32×32 takes well under a millisecond.
public enum BlurHash {
    private static let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~".utf8)
    private static let lookup: [UInt8: Int] = Dictionary(uniqueKeysWithValues: chars.enumerated().map { ($1, $0) })

    // sRGB <-> linear tables: 256 entries avoid pow() in the inner loop.
    private static let srgbToLinear: [Float] = (0..<256).map { i in
        let v = Float(i) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func linearToSRGB(_ value: Float) -> UInt8 {
        let v = max(0, min(1, value))
        let s = v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
        return UInt8(s * 255 + 0.5)
    }

    private static func decode83<S: Collection<UInt8>>(_ s: S) -> Int? {
        var value = 0
        for c in s {
            guard let digit = lookup[c] else { return nil }
            value = value * 83 + digit
        }
        return value
    }

    public static func image(_ hash: String, width: Int = 32, height: Int = 32, punch: Float = 1) -> CGImage? {
        Perf.measureSync("blurhash", .blurHashDecode) {
            decode(hash, width: width, height: height, punch: punch)
        }
    }

    static func decode(_ hash: String, width: Int, height: Int, punch: Float) -> CGImage? {
        let bytes = Array(hash.utf8)
        guard bytes.count >= 6, let sizeFlag = decode83(bytes[0..<1]) else { return nil }
        let numY = (sizeFlag / 9) + 1
        let numX = (sizeFlag % 9) + 1
        guard bytes.count == 4 + 2 * numX * numY, let quantMax = decode83(bytes[1..<2]) else { return nil }
        let maxValue = Float(quantMax + 1) / 166

        var colors = [(Float, Float, Float)](repeating: (0, 0, 0), count: numX * numY)
        guard let dc = decode83(bytes[2..<6]) else { return nil }
        colors[0] = (srgbToLinear[dc >> 16], srgbToLinear[(dc >> 8) & 255], srgbToLinear[dc & 255])

        func signPow(_ v: Float, _ e: Float) -> Float { copysign(pow(abs(v), e), v) }
        for i in 1..<colors.count {
            let start = 4 + i * 2
            guard let ac = decode83(bytes[start..<start + 2]) else { return nil }
            let r = Float(ac / (19 * 19)), g = Float((ac / 19) % 19), b = Float(ac % 19)
            colors[i] = (
                signPow((r - 9) / 9, 2) * maxValue * punch,
                signPow((g - 9) / 9, 2) * maxValue * punch,
                signPow((b - 9) / 9, 2) * maxValue * punch
            )
        }

        // Precompute cosines per axis: O(w*nx + h*ny) instead of O(w*h*nx*ny) cos() calls.
        let cosX = (0..<numX).map { i in (0..<width).map { x in Float(cos(Double.pi * Double(x) * Double(i) / Double(width))) } }
        let cosY = (0..<numY).map { j in (0..<height).map { y in Float(cos(Double.pi * Double(y) * Double(j) / Double(height))) } }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                var r: Float = 0, g: Float = 0, b: Float = 0
                for j in 0..<numY {
                    let cy = cosY[j][y]
                    for i in 0..<numX {
                        let basis = cosX[i][x] * cy
                        let c = colors[i + j * numX]
                        r += c.0 * basis
                        g += c.1 * basis
                        b += c.2 * basis
                    }
                }
                let o = y * bytesPerRow + x * 4
                pixels[o] = linearToSRGB(r)
                pixels[o + 1] = linearToSRGB(g)
                pixels[o + 2] = linearToSRGB(b)
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return unsafe CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
