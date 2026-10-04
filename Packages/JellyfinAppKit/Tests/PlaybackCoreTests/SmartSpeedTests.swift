import Foundation
@testable import PlaybackCore
import Testing

/// Smart Speed on synthetic speech: syllables (tone bursts with 60 ms gaps)
/// and pauses of room tone (−65 dB noise).
@Suite("Smart Speed")
struct SmartSpeedTests {
    static let rate = 44_100.0

    /// `pattern`: (seconds, isSpeech).
    static func signal(_ pattern: [(Double, Bool)]) -> [Float] {
        var out: [Float] = []
        var rng = SystemRandomNumberGenerator()
        for (seconds, speech) in pattern {
            let n = Int(seconds * rate)
            for i in 0..<n {
                let t = Double(i) / rate
                if speech, t.truncatingRemainder(dividingBy: 0.21) < 0.15 {
                    out.append(Float(0.3 * sin(2 * .pi * 220 * t) + 0.1 * sin(2 * .pi * 1100 * t)))
                } else {
                    out.append(Float.random(in: -0.0006...0.0006, using: &rng))      // ≈ −65 dBFS
                }
            }
        }
        return out
    }

    static func run(_ input: [Float], enabled: Bool = true) -> (chunks: [AudioChunk], saved: Double) {
        var p = SmartSpeedProcessor(sampleRate: rate, channelCount: 1, enabled: enabled)
        var chunks: [AudioChunk] = []
        var i = 0
        while i < input.count {                                   // decoder-sized blocks
            let end = min(input.count, i + 4096)
            chunks += p.process([Array(input[i..<end])], sourceStart: Double(i) / rate)
            i = end
        }
        chunks += p.flush()
        return (chunks, p.savedSeconds)
    }

    /// Long pauses shrink by the formula; a short one and the speech are
    /// untouched; output time maps back to source time.
    @Test func shortensLongPausesOnly() throws {
        let pattern: [(Double, Bool)] = [(3, true), (1.0, false), (2, true), (0.2, false), (2, true), (3.0, false), (2, true)]
        let input = Self.signal(pattern)
        let (chunks, saved) = Self.run(input)
        let expectedSaved = (1.0 - 0.475) + (3.0 - 0.9)
        #expect(abs(saved - expectedSaved) < 0.06, "saved \(saved) s, expected \(expectedSaved)")
        let outFrames = chunks.reduce(0) { $0 + $1.frameCount }
        #expect(abs(Double(input.count - outFrames) / Self.rate - saved) < 0.001, "frames out don't match the time saved")

        // Chunks run forward through the source and never overlap; exactly
        // two jumps (the cuts) — the 0.2 s gap and the syllable gaps survive.
        var jumps = 0
        for (a, b) in zip(chunks, chunks.dropFirst()) {
            let end = a.sourceStart + Double(a.frameCount) / Self.rate
            #expect(b.sourceStart >= end - 1e-6)
            if b.sourceStart - end > 1e-6 { jumps += 1 }
        }
        #expect(jumps == 2, "\(jumps) cuts")
        // Speech is bit-identical: the last two seconds come out unchanged.
        let all = chunks.flatMap { $0.channels[0] }
        #expect(Array(all.suffix(Int(2 * Self.rate))) == Array(input.suffix(Int(2 * Self.rate))))
    }

    /// Off: a pass-through. And fast enough to run far ahead of playback:
    /// ten minutes of audio in well under a second (release; debug ~3×).
    @Test func offIsPassThroughAndProcessingIsFast() {
        let input = Self.signal([(2, true), (2, false), (2, true)])
        let (off, savedOff) = Self.run(input, enabled: false)
        #expect(savedOff == 0 && off.reduce(0) { $0 + $1.frameCount } == input.count)

        let tenMinutes = Array(repeating: Self.signal([(4, true), (1.5, false)]), count: 110).flatMap { $0 }
        let start = ContinuousClock.now
        let (_, saved) = Self.run(tenMinutes)
        let elapsed = start.duration(to: .now)
        #expect(abs(saved - 110 * 0.9) < 1, "saved \(saved) s over 110 pauses of 1.5 s (0.9 s each)")
        #expect(elapsed < .seconds(4), "10 min of audio took \(elapsed)")
    }
}
