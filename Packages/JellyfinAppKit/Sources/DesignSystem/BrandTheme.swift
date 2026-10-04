// Generated from brands/bumper/brand.json by the brand kit (~/Developer/brand).
// Don't edit by hand: change brand.json and run `brand build bumper`.
import SwiftUI

enum BumperBrand {
    static let name = "bumper"
    static let tagline = "Keeps things playing"

    enum Palette {
        /// #0E0D0B
        static let ink = Color(red: 0.0549, green: 0.0510, blue: 0.0431)
        /// #171614
        static let soot = Color(red: 0.0902, green: 0.0863, blue: 0.0784)
        /// #23211E
        static let graphite = Color(red: 0.1373, green: 0.1294, blue: 0.1176)
        /// #3A3833
        static let ash = Color(red: 0.2275, green: 0.2196, blue: 0.2000)
        /// #EBE4D2
        static let paper = Color(red: 0.9216, green: 0.8941, blue: 0.8235)
        /// #D15B60
        static let plate = Color(red: 0.8196, green: 0.3569, blue: 0.3765)
        /// #00E6EF
        static let signal = Color(red: 0.0000, green: 0.9020, blue: 0.9373)
    }

    /// The ink boil. Lengths are fractions of the wordmark's height, so they hold at any size.
    enum Boil {
        static let framesPerSecond: Double = 8
        static let frames = 4
        static let noiseCyclesPerMarkHeight: Double = 7.951
        static let octaves = 2
        static let edgeTravel: Double = 0.00424
        static let plateOffset = CGSize(width: 0.05093, height: 0.03565)
    }
}
